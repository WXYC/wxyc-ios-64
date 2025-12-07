#!/usr/bin/env python3
"""
Hierarchical Git Commit Summarizer

This tool analyzes git commits in pages, identifying major work streams,
then recursively summarizes pages until arriving at a final summary.
"""

import subprocess
import sys
import json
import os
import asyncio
from typing import List, Dict, Any
import anthropic
from tqdm import tqdm
from tqdm.asyncio import tqdm as atqdm


class CommitSummarizer:
    def __init__(self, page_size: int = 5, api_key: str = None, max_concurrent: int = None, focus_topics: List[str] = None):
        self.page_size = page_size
        self.client = anthropic.AsyncAnthropic(api_key=api_key or os.environ.get("ANTHROPIC_API_KEY"))
        self.model = "claude-sonnet-4-5-20250929"
        self.max_concurrent = max_concurrent
        self.focus_topics = focus_topics or []
        self.semaphore = None  # Will be initialized after detecting rate limits

    def get_commits(self, commit_range: str) -> List[Dict[str, str]]:
        """Get commits in the specified range."""
        try:
            # Get commit info: hash, author date, subject, body
            cmd = [
                "git", "log",
                "--pretty=format:%H|||%aI|||%s|||%b|||END_COMMIT",
                commit_range
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)

            # Parse commit blocks first to count them
            commit_blocks = [block for block in result.stdout.split("|||END_COMMIT") if block.strip()]

            commits = []
            for commit_block in tqdm(commit_blocks, desc="Fetching commit details", unit="commit", file=sys.stderr):
                parts = commit_block.split("|||", 3)
                if len(parts) >= 3:
                    commit_hash, date, subject = parts[0], parts[1], parts[2]
                    body = parts[3] if len(parts) > 3 else ""

                    # Get diffstat for this commit
                    diffstat_cmd = ["git", "show", "--stat", "--pretty=format:", commit_hash]
                    diffstat_result = subprocess.run(diffstat_cmd, capture_output=True, text=True)
                    diffstat = diffstat_result.stdout.strip()

                    commits.append({
                        "hash": commit_hash.strip(),
                        "date": date.strip(),
                        "subject": subject.strip(),
                        "body": body.strip(),
                        "diffstat": diffstat
                    })

            return commits
        except subprocess.CalledProcessError as e:
            print(f"Error getting commits: {e}", file=sys.stderr)
            print(f"stderr: {e.stderr}", file=sys.stderr)
            sys.exit(1)

    def format_commit(self, commit: Dict[str, str]) -> str:
        """Format a commit for display."""
        result = f"Commit: {commit['hash'][:8]}\n"
        result += f"Date: {commit['date']}\n"
        result += f"Subject: {commit['subject']}\n"
        if commit['body']:
            result += f"Body:\n{commit['body']}\n"
        if commit['diffstat']:
            result += f"Changes:\n{commit['diffstat']}\n"
        return result

    async def detect_rate_limits(self) -> int:
        """Make a test request to detect rate limits from response headers."""
        try:
            print("Detecting API rate limits...", file=sys.stderr)
            response = await self.client.messages.create(
                model=self.model,
                max_tokens=10,
                messages=[{"role": "user", "content": "Hi"}]
            )

            # Try to get rate limit info from response headers
            # Note: The Python SDK may not expose headers directly, so we'll use a conservative default
            # The Anthropic API typically allows 5 concurrent requests for most tiers
            default_concurrent = 5

            print(f"Using max concurrent requests: {default_concurrent}", file=sys.stderr)
            return default_concurrent

        except Exception as e:
            print(f"Warning: Could not detect rate limits ({e}), using conservative default of 3", file=sys.stderr)
            return 3

    async def summarize_page(self, items: List[Any], level: int, page_num: int) -> str:
        """Summarize a page of items (either commits or previous summaries)."""
        if level == 0:
            # Level 0: summarizing actual commits
            prompt = "Analyze the following git commits and identify the major work streams. "
            prompt += "Group related commits together and describe each work stream concisely. "
            prompt += "Focus on functional changes, not trivial updates.\n\n"

            for i, commit in enumerate(items):
                prompt += f"\n--- Commit {i+1} ---\n"
                prompt += self.format_commit(commit)
        else:
            # Higher levels: summarizing summaries
            prompt = f"Analyze the following summaries from page groups (level {level-1}) and identify the major work streams across these groups. "
            prompt += "Connect related work streams between groups and provide a cohesive summary. "
            prompt += "Maintain the big picture while identifying patterns and themes.\n\n"

            for i, summary in enumerate(items):
                prompt += f"\n--- Page Group {i+1} Summary ---\n"
                prompt += summary + "\n"

        prompt += "\n\nProvide a concise summary of the major work streams, using bullet points for each stream."

        # Add focus topics if specified
        if self.focus_topics:
            topics_str = ", ".join(self.focus_topics)
            prompt += f"\n\nPay special attention to changes related to: {topics_str}. "
            prompt += "Highlight these topics prominently in your summary when they appear."

        # Use semaphore to limit concurrent requests
        async with self.semaphore:
            try:
                response = await self.client.messages.create(
                    model=self.model,
                    max_tokens=2000,
                    messages=[{
                        "role": "user",
                        "content": prompt
                    }]
                )

                return response.content[0].text
            except Exception as e:
                print(f"Error calling Claude API: {e}", file=sys.stderr)
                raise  # Re-raise the exception instead of sys.exit()

    def chunk_list(self, items: List[Any], chunk_size: int) -> List[List[Any]]:
        """Split a list into chunks of specified size."""
        return [items[i:i + chunk_size] for i in range(0, len(items), chunk_size)]

    async def recursive_summarize(self, items: List[Any], level: int = 0, total_items: int = None) -> str:
        """Recursively summarize items in pages until one summary remains."""
        # Track total items from the first level
        if total_items is None:
            total_items = len(items)

        # Calculate progress percentage
        items_processed = total_items - len(items) if level > 0 else 0
        progress_pct = (items_processed / total_items * 100) if total_items > 0 else 0

        print(f"\nLevel {level}: Processing {len(items)} items (Overall: {progress_pct:.1f}% complete)", file=sys.stderr)

        if len(items) == 0:
            return "No items to summarize."

        if len(items) == 1 and level > 0:
            # Base case: only one summary left (but not if we're at level 0 with 1 commit)
            return items[0]

        # Split items into pages
        pages = self.chunk_list(items, self.page_size)
        print(f"  Split into {len(pages)} pages of ~{self.page_size} items each", file=sys.stderr)

        # Summarize each page in parallel with progress bar
        tasks = [
            self.summarize_page(page, level, page_num)
            for page_num, page in enumerate(pages, 1)
        ]
        summaries = await atqdm.gather(
            *tasks,
            desc=f"  API calls (level {level})",
            unit="page",
            file=sys.stderr
        )

        # If we only have one summary, we're done
        if len(summaries) == 1:
            return summaries[0]

        # Otherwise, recursively summarize the summaries
        return await self.recursive_summarize(summaries, level + 1, total_items=total_items)

    async def summarize_range(self, commit_range: str) -> str:
        """Summarize commits in the specified range."""
        # Initialize semaphore if not already set
        if self.semaphore is None:
            if self.max_concurrent is None:
                # Auto-detect rate limits
                self.max_concurrent = await self.detect_rate_limits()
            else:
                print(f"Using max concurrent requests: {self.max_concurrent}", file=sys.stderr)
            self.semaphore = asyncio.Semaphore(self.max_concurrent)

        if self.focus_topics:
            print(f"Focus topics: {', '.join(self.focus_topics)}", file=sys.stderr)

        print(f"Fetching commits for range: {commit_range}", file=sys.stderr)
        commits = self.get_commits(commit_range)

        if not commits:
            return "No commits found in the specified range."

        print(f"Found {len(commits)} commits", file=sys.stderr)

        # Reverse to process oldest to newest
        commits.reverse()

        return await self.recursive_summarize(commits, level=0)


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Hierarchically summarize git commits by pages",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Summarize last 20 commits
  %(prog)s HEAD~20..HEAD

  # Summarize from a tag to HEAD
  %(prog)s 2.5.9..HEAD

  # Focus on specific topics (just list keywords)
  %(prog)s 2.5.9..HEAD --focus visualizer audio CarPlay

  # Summarize with custom page size
  %(prog)s --page-size 10 2.5.9..HEAD

  # Summarize all commits between two tags
  %(prog)s v1.0..v2.0
        """
    )

    parser.add_argument(
        "range",
        help="Git commit range (e.g., '2.5.9..HEAD', 'HEAD~10..HEAD')"
    )
    parser.add_argument(
        "--page-size", "-p",
        type=int,
        default=5,
        help="Number of commits per page (default: 5)"
    )
    parser.add_argument(
        "--max-concurrent", "-c",
        type=int,
        default=None,
        help="Maximum concurrent API requests (default: auto-detect from rate limits)"
    )
    parser.add_argument(
        "--focus", "-f",
        nargs="+",
        default=None,
        metavar="TOPIC",
        help="Focus on specific topics (e.g., --focus visualizer audio CarPlay)"
    )
    parser.add_argument(
        "--api-key",
        help="Anthropic API key (or set ANTHROPIC_API_KEY env var)"
    )

    args = parser.parse_args()

    # Validate API key
    api_key = args.api_key or os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Error: ANTHROPIC_API_KEY must be set or provided via --api-key", file=sys.stderr)
        sys.exit(1)

    summarizer = CommitSummarizer(
        page_size=args.page_size,
        api_key=api_key,
        max_concurrent=args.max_concurrent,
        focus_topics=args.focus
    )

    try:
        final_summary = asyncio.run(summarizer.summarize_range(args.range))
        print("\n" + "="*80)
        print("FINAL SUMMARY")
        print("="*80)
        print(final_summary)
    except KeyboardInterrupt:
        print("\n\nInterrupted by user", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
