//
//  WXYCLogoShape.swift
//  WXUI
//
//  Created by Jake Bromberg on 11/25/25.
//

import Foundation
import SwiftUI

public struct WXYCLogoShape: Shape {
    // Original aspect ratio from SVG viewBox: 2000 x 750
    private static let aspectRatio: CGFloat = 2000 / 750

    public init() {}

    public func path(
        in rect: CGRect
    ) -> Path {
        var path = Path()
        
        // Calculate aspect-fit dimensions
        let rectAspect = rect.size.width / rect.size.height
        let width: CGFloat
        let height: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        
        if rectAspect > Self.aspectRatio {
            // Rect is wider than logo - fit to height
            height = rect.size.height
            width = height * Self.aspectRatio
            offsetX = (
                rect.size.width - width
            ) / 2
            offsetY = 0
        } else {
            // Rect is taller than logo - fit to width
            width = rect.size.width
            height = width / Self.aspectRatio
            offsetX = 0
            offsetY = (
                rect.size.height - height
            ) / 2
        }
        path
            .move(
                to: CGPoint(
                    x: 0.32842*width,
                    y: 0.03917*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.31213*width,
                    y: 0.19333*height
                ),
                control1: CGPoint(
                    x: 0.32342*width,
                    y: 0.09102*height
                ),
                control2: CGPoint(
                    x: 0.31659*width,
                    y: 0.14079*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.29847*width,
                    y: 0.32923*height
                ),
                control1: CGPoint(
                    x: 0.30397*width,
                    y: 0.23535*height
                ),
                control2: CGPoint(
                    x: 0.30345*width,
                    y: 0.2844*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.294*width,
                    y: 0.45323*height
                ),
                control1: CGPoint(
                    x: 0.29924*width,
                    y: 0.3713*height
                ),
                control2: CGPoint(
                    x: 0.29372*width,
                    y: 0.41115*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.26248*width,
                    y: 0.35097*height
                ),
                control1: CGPoint(
                    x: 0.28374*width,
                    y: 0.4189*height
                ),
                control2: CGPoint(
                    x: 0.27299*width,
                    y: 0.3853*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.24303*width,
                    y: 0.24939*height
                ),
                control1: CGPoint(
                    x: 0.25407*width,
                    y: 0.31941*height
                ),
                control2: CGPoint(
                    x: 0.25143*width,
                    y: 0.28018*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.20439*width,
                    y: 0.14142*height
                ),
                control1: CGPoint(
                    x: 0.23357*width,
                    y: 0.20591*height
                ),
                control2: CGPoint(
                    x: 0.21938*width,
                    y: 0.17159*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.19632*width,
                    y: 0.1409*height
                ),
                control1: CGPoint(
                    x: 0.20173*width,
                    y: 0.14144*height
                ),
                control2: CGPoint(
                    x: 0.19903*width,
                    y: 0.14117*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.17577*width,
                    y: 0.14355*height
                ),
                control1: CGPoint(
                    x: 0.18939*width,
                    y: 0.14021*height
                ),
                control2: CGPoint(
                    x: 0.18238*width,
                    y: 0.13952*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.16631*width,
                    y: 0.22344*height
                ),
                control1: CGPoint(
                    x: 0.17105*width,
                    y: 0.16882*height
                ),
                control2: CGPoint(
                    x: 0.1713*width,
                    y: 0.19895*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.15659*width,
                    y: 0.29418*height
                ),
                control1: CGPoint(
                    x: 0.16289*width,
                    y: 0.24654*height
                ),
                control2: CGPoint(
                    x: 0.15817*width,
                    y: 0.26896*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.14817*width,
                    y: 0.41401*height
                ),
                control1: CGPoint(
                    x: 0.15633*width,
                    y: 0.33485*height
                ),
                control2: CGPoint(
                    x: 0.1508*width,
                    y: 0.37412*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.14214*width,
                    y: 0.55205*height
                ),
                control1: CGPoint(
                    x: 0.1395*width,
                    y: 0.45671*height
                ),
                control2: CGPoint(
                    x: 0.14503*width,
                    y: 0.5058*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.13006*width,
                    y: 0.51491*height
                ),
                control1: CGPoint(
                    x: 0.13557*width,
                    y: 0.54929*height
                ),
                control2: CGPoint(
                    x: 0.13426*width,
                    y: 0.52609*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.09012*width,
                    y: 0.33417*height
                ),
                control1: CGPoint(
                    x: 0.11796*width,
                    y: 0.45255*height
                ),
                control2: CGPoint(
                    x: 0.10115*width,
                    y: 0.39793*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.05937*width,
                    y: 0.19889*height
                ),
                control1: CGPoint(
                    x: 0.08039*width,
                    y: 0.28861*height
                ),
                control2: CGPoint(
                    x: 0.07173*width,
                    y: 0.24029*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.04755*width,
                    y: 0.14636*height
                ),
                control1: CGPoint(
                    x: 0.05439*width,
                    y: 0.18277*height
                ),
                control2: CGPoint(
                    x: 0.05333*width,
                    y: 0.1604*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.02232*width,
                    y: 0.14147*height
                ),
                control1: CGPoint(
                    x: 0.04178*width,
                    y: 0.12748*height
                ),
                control2: CGPoint(
                    x: 0.0289*width,
                    y: 0.12254*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.02338*width,
                    y: 0.17159*height
                ),
                control1: CGPoint(
                    x: 0.02207*width,
                    y: 0.1513*height
                ),
                control2: CGPoint(
                    x: 0.02365*width,
                    y: 0.16176*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.01848*width,
                    y: 0.17122*height
                ),
                control1: CGPoint(
                    x: 0.02178*width,
                    y: 0.17454*height
                ),
                control2: CGPoint(
                    x: 0.02012*width,
                    y: 0.17288*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.01313*width,
                    y: 0.17227*height
                ),
                control1: CGPoint(
                    x: 0.01663*width,
                    y: 0.16934*height
                ),
                control2: CGPoint(
                    x: 0.01481*width,
                    y: 0.16746*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0,
                    y: 0.25666*height
                ),
                control1: CGPoint(
                    x: 0.00094*width,
                    y: 0.18824*height
                ),
                control2: CGPoint(
                    x: 0.00054*width,
                    y: 0.22601*height
                )
            )
        path
            .addLine(
                to: CGPoint(
                    x: 0,
                    y: 0.25832*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.00761*width,
                    y: 0.32367*height
                ),
                control1: CGPoint(
                    x: 0.00085*width,
                    y: 0.28125*height
                ),
                control2: CGPoint(
                    x: 0.00474*width,
                    y: 0.3021*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.02863*width,
                    y: 0.42103*height
                ),
                control1: CGPoint(
                    x: 0.01207*width,
                    y: 0.35934*height
                ),
                control2: CGPoint(
                    x: 0.02179*width,
                    y: 0.38806*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.05308*width,
                    y: 0.54575*height
                ),
                control1: CGPoint(
                    x: 0.03652*width,
                    y: 0.46305*height
                ),
                control2: CGPoint(
                    x: 0.04808*width,
                    y: 0.50024*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.06463*width,
                    y: 0.61857*height
                ),
                control1: CGPoint(
                    x: 0.05727*width,
                    y: 0.57025*height
                ),
                control2: CGPoint(
                    x: 0.05911*width,
                    y: 0.5962*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.08539*width,
                    y: 0.7461*height
                ),
                control1: CGPoint(
                    x: 0.07146*width,
                    y: 0.66137*height
                ),
                control2: CGPoint(
                    x: 0.07804*width,
                    y: 0.70407*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.10535*width,
                    y: 0.83228*height
                ),
                control1: CGPoint(
                    x: 0.09195*width,
                    y: 0.77486*height
                ),
                control2: CGPoint(
                    x: 0.09957*width,
                    y: 0.80217*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.14397*width,
                    y: 0.94644*height
                ),
                control1: CGPoint(
                    x: 0.11638*width,
                    y: 0.8743*height
                ),
                control2: CGPoint(
                    x: 0.12611*width,
                    y: 0.9234*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.16763*width,
                    y: 0.95487*height
                ),
                control1: CGPoint(
                    x: 0.15186*width,
                    y: 0.95071*height
                ),
                control2: CGPoint(
                    x: 0.15973*width,
                    y: 0.95206*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.18287*width,
                    y: 0.96116*height
                ),
                control1: CGPoint(
                    x: 0.17184*width,
                    y: 0.96611*height
                ),
                control2: CGPoint(
                    x: 0.1776*width,
                    y: 0.9724*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.19442*width,
                    y: 0.86665*height
                ),
                control1: CGPoint(
                    x: 0.191*width,
                    y: 0.93531*height
                ),
                control2: CGPoint(
                    x: 0.19257*width,
                    y: 0.89948*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.20599*width,
                    y: 0.81969*height
                ),
                control1: CGPoint(
                    x: 0.19863*width,
                    y: 0.85126*height
                ),
                control2: CGPoint(
                    x: 0.20309*width,
                    y: 0.83722*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.21203*width,
                    y: 0.71666*height
                ),
                control1: CGPoint(
                    x: 0.2157*width,
                    y: 0.79093*height
                ),
                control2: CGPoint(
                    x: 0.21017*width,
                    y: 0.75104*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.21464*width,
                    y: 0.58991*height
                ),
                control1: CGPoint(
                    x: 0.21518*width,
                    y: 0.67463*height
                ),
                control2: CGPoint(
                    x: 0.21412*width,
                    y: 0.63193*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.21624*width,
                    y: 0.58284*height
                ),
                control1: CGPoint(
                    x: 0.21491*width,
                    y: 0.58845*height
                ),
                control2: CGPoint(
                    x: 0.21597*width,
                    y: 0.58497*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.2404*width,
                    y: 0.67599*height
                ),
                control1: CGPoint(
                    x: 0.227*width,
                    y: 0.60531*height
                ),
                control2: CGPoint(
                    x: 0.23305*width,
                    y: 0.64452*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.27562*width,
                    y: 0.81339*height
                ),
                control1: CGPoint(
                    x: 0.25222*width,
                    y: 0.7216*height
                ),
                control2: CGPoint(
                    x: 0.26062*width,
                    y: 0.77418*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.30293*width,
                    y: 0.86036*height
                ),
                control1: CGPoint(
                    x: 0.28428*width,
                    y: 0.83092*height
                ),
                control2: CGPoint(
                    x: 0.29241*width,
                    y: 0.85184*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.31501*width,
                    y: 0.85465*height
                ),
                control1: CGPoint(
                    x: 0.30715*width,
                    y: 0.85959*height
                ),
                control2: CGPoint(
                    x: 0.31081*width,
                    y: 0.85184*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.32606*width,
                    y: 0.89047*height
                ),
                control1: CGPoint(
                    x: 0.31763*width,
                    y: 0.86869*height
                ),
                control2: CGPoint(
                    x: 0.31974*width,
                    y: 0.88689*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.33472*width,
                    y: 0.85465*height
                ),
                control1: CGPoint(
                    x: 0.33131*width,
                    y: 0.8834*height
                ),
                control2: CGPoint(
                    x: 0.33131*width,
                    y: 0.86588*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.34366*width,
                    y: 0.82318*height
                ),
                control1: CGPoint(
                    x: 0.33788*width,
                    y: 0.84419*height
                ),
                control2: CGPoint(
                    x: 0.3405*width,
                    y: 0.83296*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.35732*width,
                    y: 0.78328*height
                ),
                control1: CGPoint(
                    x: 0.35022*width,
                    y: 0.81621*height
                ),
                control2: CGPoint(
                    x: 0.35784*width,
                    y: 0.8042*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.36099*width,
                    y: 0.61508*height
                ),
                control1: CGPoint(
                    x: 0.3568*width,
                    y: 0.72721*height
                ),
                control2: CGPoint(
                    x: 0.36178*width,
                    y: 0.67115*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.36152*width,
                    y: 0.36429*height
                ),
                control1: CGPoint(
                    x: 0.36231*width,
                    y: 0.53171*height
                ),
                control2: CGPoint(
                    x: 0.36284*width,
                    y: 0.44766*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.36546*width,
                    y: 0.26474*height
                ),
                control1: CGPoint(
                    x: 0.36546*width,
                    y: 0.33204*height
                ),
                control2: CGPoint(
                    x: 0.36361*width,
                    y: 0.29771*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.36676*width,
                    y: 0.10361*height
                ),
                control1: CGPoint(
                    x: 0.36861*width,
                    y: 0.21148*height
                ),
                control2: CGPoint(
                    x: 0.36468*width,
                    y: 0.15755*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.34733*width,
                    y: 0.04057*height
                ),
                control1: CGPoint(
                    x: 0.36414*width,
                    y: 0.07703*height
                ),
                control2: CGPoint(
                    x: 0.34733*width,
                    y: 0.04057*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.33893*width,
                    y: 0
                ),
                control1: CGPoint(
                    x: 0.34733*width,
                    y: 0.04057*height
                ),
                control2: CGPoint(
                    x: 0.33997*width,
                    y: 0.01186*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.32842*width,
                    y: 0.03917*height
                ),
                control1: CGPoint(
                    x: 0.33261*width,
                    y: 0.00557*height
                ),
                control2: CGPoint(
                    x: 0.33*width,
                    y: 0.02382*height
                )
            )
        path
            .move(
                to: CGPoint(
                    x: 0.56488*width,
                    y: 0.02518*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.52784*width,
                    y: 0.12254*height
                ),
                control1: CGPoint(
                    x: 0.55357*width,
                    y: 0.06018*height
                ),
                control2: CGPoint(
                    x: 0.53965*width,
                    y: 0.08894*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.50103*width,
                    y: 0.19821*height
                ),
                control1: CGPoint(
                    x: 0.51968*width,
                    y: 0.14912*height
                ),
                control2: CGPoint(
                    x: 0.50943*width,
                    y: 0.17227*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.48921*width,
                    y: 0.24867*height
                ),
                control1: CGPoint(
                    x: 0.49894*width,
                    y: 0.21855*height
                ),
                control2: CGPoint(
                    x: 0.49237*width,
                    y: 0.23041*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.4808*width,
                    y: 0.28721*height
                ),
                control1: CGPoint(
                    x: 0.48921*width,
                    y: 0.24867*height
                ),
                control2: CGPoint(
                    x: 0.48435*width,
                    y: 0.28004*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.4759*width,
                    y: 0.29128*height
                ),
                control1: CGPoint(
                    x: 0.47845*width,
                    y: 0.29196*height
                ),
                control2: CGPoint(
                    x: 0.47713*width,
                    y: 0.29162*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.47397*width,
                    y: 0.29142*height
                ),
                control1: CGPoint(
                    x: 0.47527*width,
                    y: 0.29111*height
                ),
                control2: CGPoint(
                    x: 0.47467*width,
                    y: 0.29093*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.46242*width,
                    y: 0.25288*height
                ),
                control1: CGPoint(
                    x: 0.46846*width,
                    y: 0.28232*height
                ),
                control2: CGPoint(
                    x: 0.46556*width,
                    y: 0.26687*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.42536*width,
                    y: 0.11344*height
                ),
                control1: CGPoint(
                    x: 0.4519*width,
                    y: 0.20316*height
                ),
                control2: CGPoint(
                    x: 0.43691*width,
                    y: 0.16108*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.39593*width,
                    y: 0.06507*height
                ),
                control1: CGPoint(
                    x: 0.42143*width,
                    y: 0.08047*height
                ),
                control2: CGPoint(
                    x: 0.4075*width,
                    y: 0.0672*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.38044*width,
                    y: 0.0581*height
                ),
                control1: CGPoint(
                    x: 0.39173*width,
                    y: 0.05461*height
                ),
                control2: CGPoint(
                    x: 0.38515*width,
                    y: 0.04546*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.3765*width,
                    y: 0.12467*height
                ),
                control1: CGPoint(
                    x: 0.37177*width,
                    y: 0.07282*height
                ),
                control2: CGPoint(
                    x: 0.37465*width,
                    y: 0.10293*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.38595*width,
                    y: 0.19753*height
                ),
                control1: CGPoint(
                    x: 0.37675*width,
                    y: 0.1513*height
                ),
                control2: CGPoint(
                    x: 0.38333*width,
                    y: 0.17227*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.42694*width,
                    y: 0.43788*height
                ),
                control1: CGPoint(
                    x: 0.39935*width,
                    y: 0.27738*height
                ),
                control2: CGPoint(
                    x: 0.41222*width,
                    y: 0.35867*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.42851*width,
                    y: 0.47284*height
                ),
                control1: CGPoint(
                    x: 0.42879*width,
                    y: 0.44833*height
                ),
                control2: CGPoint(
                    x: 0.43115*width,
                    y: 0.46165*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.38279*width,
                    y: 0.71037*height
                ),
                control1: CGPoint(
                    x: 0.41197*width,
                    y: 0.54992*height
                ),
                control2: CGPoint(
                    x: 0.39777*width,
                    y: 0.63048*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.37045*width,
                    y: 0.77621*height
                ),
                control1: CGPoint(
                    x: 0.37702*width,
                    y: 0.72925*height
                ),
                control2: CGPoint(
                    x: 0.36941*width,
                    y: 0.74958*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.36387*width,
                    y: 0.85329*height
                ),
                control1: CGPoint(
                    x: 0.37152*width,
                    y: 0.80352*height
                ),
                control2: CGPoint(
                    x: 0.36415*width,
                    y: 0.82598*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.37203*width,
                    y: 0.95632*height
                ),
                control1: CGPoint(
                    x: 0.36389*width,
                    y: 0.88835*height
                ),
                control2: CGPoint(
                    x: 0.36204*width,
                    y: 0.92892*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.38279*width,
                    y: 0.9479*height
                ),
                control1: CGPoint(
                    x: 0.3757*width,
                    y: 0.95632*height
                ),
                control2: CGPoint(
                    x: 0.38043*width,
                    y: 0.95845*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.43035*width,
                    y: 0.88554*height
                ),
                control1: CGPoint(
                    x: 0.40068*width,
                    y: 0.94228*height
                ),
                control2: CGPoint(
                    x: 0.41827*width,
                    y: 0.92059*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.454*width,
                    y: 0.80139*height
                ),
                control1: CGPoint(
                    x: 0.43718*width,
                    y: 0.85475*height
                ),
                control2: CGPoint(
                    x: 0.44823*width,
                    y: 0.83296*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.48106*width,
                    y: 0.69981*height
                ),
                control1: CGPoint(
                    x: 0.46265*width,
                    y: 0.76711*height
                ),
                control2: CGPoint(
                    x: 0.46634*width,
                    y: 0.71811*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.51259*width,
                    y: 0.81891*height
                ),
                control1: CGPoint(
                    x: 0.49104*width,
                    y: 0.7398*height
                ),
                control2: CGPoint(
                    x: 0.50155*width,
                    y: 0.78047*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.54175*width,
                    y: 0.87285*height
                ),
                control1: CGPoint(
                    x: 0.52101*width,
                    y: 0.84138*height
                ),
                control2: CGPoint(
                    x: 0.52968*width,
                    y: 0.86665*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.56488*width,
                    y: 0.85126*height
                ),
                control1: CGPoint(
                    x: 0.54964*width,
                    y: 0.86733*height
                ),
                control2: CGPoint(
                    x: 0.55673*width,
                    y: 0.8561*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.57933*width,
                    y: 0.79791*height
                ),
                control1: CGPoint(
                    x: 0.57354*width,
                    y: 0.84555*height
                ),
                control2: CGPoint(
                    x: 0.57933*width,
                    y: 0.82037*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.55594*width,
                    y: 0.69003*height
                ),
                control1: CGPoint(
                    x: 0.57539*width,
                    y: 0.75656*height
                ),
                control2: CGPoint(
                    x: 0.56464*width,
                    y: 0.72373*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.54227*width,
                    y: 0.58632*height
                ),
                control1: CGPoint(
                    x: 0.5591*width,
                    y: 0.65217*height
                ),
                control2: CGPoint(
                    x: 0.54909*width,
                    y: 0.61789*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.51968*width,
                    y: 0.49879*height
                ),
                control1: CGPoint(
                    x: 0.53439*width,
                    y: 0.55766*height
                ),
                control2: CGPoint(
                    x: 0.52754*width,
                    y: 0.52755*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.52546*width,
                    y: 0.44625*height
                ),
                control1: CGPoint(
                    x: 0.51442*width,
                    y: 0.47918*height
                ),
                control2: CGPoint(
                    x: 0.52309*width,
                    y: 0.46373*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.54387*width,
                    y: 0.37479*height
                ),
                control1: CGPoint(
                    x: 0.52994*width,
                    y: 0.41958*height
                ),
                control2: CGPoint(
                    x: 0.53885*width,
                    y: 0.40069*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.56462*width,
                    y: 0.23463*height
                ),
                control1: CGPoint(
                    x: 0.5536*width,
                    y: 0.33137*height
                ),
                control2: CGPoint(
                    x: 0.55594*width,
                    y: 0.27951*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.58879*width,
                    y: 0.09591*height
                ),
                control1: CGPoint(
                    x: 0.57566*width,
                    y: 0.1926*height
                ),
                control2: CGPoint(
                    x: 0.58038*width,
                    y: 0.14147*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.57905*width,
                    y: 0.01816*height
                ),
                control1: CGPoint(
                    x: 0.58746*width,
                    y: 0.06861*height
                ),
                control2: CGPoint(
                    x: 0.58404*width,
                    y: 0.04198*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.57338*width,
                    y: 0.01415*height
                ),
                control1: CGPoint(
                    x: 0.57736*width,
                    y: 0.0155*height
                ),
                control2: CGPoint(
                    x: 0.57537*width,
                    y: 0.01415*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.56488*width,
                    y: 0.02518*height
                ),
                control1: CGPoint(
                    x: 0.57011*width,
                    y: 0.01415*height
                ),
                control2: CGPoint(
                    x: 0.56684*width,
                    y: 0.01778*height
                )
            )
        path
            .move(
                to: CGPoint(
                    x: 0.8029*width,
                    y: 0.05737*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.78847*width,
                    y: 0.10574*height
                ),
                control1: CGPoint(
                    x: 0.7974*width,
                    y: 0.07209*height
                ),
                control2: CGPoint(
                    x: 0.79502*width,
                    y: 0.0931*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.77558*width,
                    y: 0.08894*height
                ),
                control1: CGPoint(
                    x: 0.78348*width,
                    y: 0.10434*height
                ),
                control2: CGPoint(
                    x: 0.78137*width,
                    y: 0.084*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.75718*width,
                    y: 0.10361*height
                ),
                control1: CGPoint(
                    x: 0.76955*width,
                    y: 0.09383*height
                ),
                control2: CGPoint(
                    x: 0.76218*width,
                    y: 0.09242*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.707*width,
                    y: 0.2767*height
                ),
                control1: CGPoint(
                    x: 0.73643*width,
                    y: 0.15198*height
                ),
                control2: CGPoint(
                    x: 0.72305*width,
                    y: 0.21855*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.69651*width,
                    y: 0.25075*height
                ),
                control1: CGPoint(
                    x: 0.70255*width,
                    y: 0.27181*height
                ),
                control2: CGPoint(
                    x: 0.70017*width,
                    y: 0.25917*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.65972*width,
                    y: 0.15333*height
                ),
                control1: CGPoint(
                    x: 0.68418*width,
                    y: 0.21928*height
                ),
                control2: CGPoint(
                    x: 0.67102*width,
                    y: 0.18839*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.62479*width,
                    y: 0.07979*height
                ),
                control1: CGPoint(
                    x: 0.64974*width,
                    y: 0.12322*height
                ),
                control2: CGPoint(
                    x: 0.63792*width,
                    y: 0.09804*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.59745*width,
                    y: 0.09804*height
                ),
                control1: CGPoint(
                    x: 0.61478*width,
                    y: 0.06788*height
                ),
                control2: CGPoint(
                    x: 0.60507*width,
                    y: 0.07984*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.61295*width,
                    y: 0.2157*height
                ),
                control1: CGPoint(
                    x: 0.59772*width,
                    y: 0.14075*height
                ),
                control2: CGPoint(
                    x: 0.60692*width,
                    y: 0.17721*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.67234*width,
                    y: 0.41193*height
                ),
                control1: CGPoint(
                    x: 0.6274*width,
                    y: 0.29064*height
                ),
                control2: CGPoint(
                    x: 0.65079*width,
                    y: 0.35237*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.63107*width,
                    y: 0.62205*height
                ),
                control1: CGPoint(
                    x: 0.65894*width,
                    y: 0.48266*height
                ),
                control2: CGPoint(
                    x: 0.64318*width,
                    y: 0.54924*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.6001*width,
                    y: 0.79791*height
                ),
                control1: CGPoint(
                    x: 0.61951*width,
                    y: 0.6788*height
                ),
                control2: CGPoint(
                    x: 0.61242*width,
                    y: 0.74184*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.58853*width,
                    y: 0.86036*height
                ),
                control1: CGPoint(
                    x: 0.5964*width,
                    y: 0.81891*height
                ),
                control2: CGPoint(
                    x: 0.59062*width,
                    y: 0.8379*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.58984*width,
                    y: 0.92902*height
                ),
                control1: CGPoint(
                    x: 0.58746*width,
                    y: 0.8834*height
                ),
                control2: CGPoint(
                    x: 0.58746*width,
                    y: 0.90655*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.60429*width,
                    y: 0.92543*height
                ),
                control1: CGPoint(
                    x: 0.59458*width,
                    y: 0.93173*height
                ),
                control2: CGPoint(
                    x: 0.59955*width,
                    y: 0.92679*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.61559*width,
                    y: 0.9997*height
                ),
                control1: CGPoint(
                    x: 0.60425*width,
                    y: 0.95341*height
                ),
                control2: CGPoint(
                    x: 0.60821*width,
                    y: 0.97937*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.63107*width,
                    y: 0.98004*height
                ),
                control1: CGPoint(
                    x: 0.62108*width,
                    y: 0.99554*height
                ),
                control2: CGPoint(
                    x: 0.62502*width,
                    y: 0.98082*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.6692*width,
                    y: 0.9051*height
                ),
                control1: CGPoint(
                    x: 0.6479*width,
                    y: 0.97656*height
                ),
                control2: CGPoint(
                    x: 0.66446*width,
                    y: 0.94993*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.69389*width,
                    y: 0.78251*height
                ),
                control1: CGPoint(
                    x: 0.681*width,
                    y: 0.87004*height
                ),
                control2: CGPoint(
                    x: 0.68598*width,
                    y: 0.82385*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.71043*width,
                    y: 0.69216*height
                ),
                control1: CGPoint(
                    x: 0.69861*width,
                    y: 0.75161*height
                ),
                control2: CGPoint(
                    x: 0.7057*width,
                    y: 0.72373*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.73513*width,
                    y: 0.54924*height
                ),
                control1: CGPoint(
                    x: 0.72042*width,
                    y: 0.64665*height
                ),
                control2: CGPoint(
                    x: 0.72672*width,
                    y: 0.59688*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.7769*width,
                    y: 0.3026*height
                ),
                control1: CGPoint(
                    x: 0.75457*width,
                    y: 0.47429*height
                ),
                control2: CGPoint(
                    x: 0.76745*width,
                    y: 0.38951*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.8079*width,
                    y: 0.10293*height
                ),
                control1: CGPoint(
                    x: 0.78453*width,
                    y: 0.23322*height
                ),
                control2: CGPoint(
                    x: 0.79843*width,
                    y: 0.17091*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.80442*width,
                    y: 0.05692*height
                ),
                control1: CGPoint(
                    x: 0.8074*width,
                    y: 0.08982*height
                ),
                control2: CGPoint(
                    x: 0.81128*width,
                    y: 0.05692*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.8029*width,
                    y: 0.05737*height
                ),
                control1: CGPoint(
                    x: 0.80397*width,
                    y: 0.05692*height
                ),
                control2: CGPoint(
                    x: 0.80346*width,
                    y: 0.05707*height
                )
            )
        path
            .move(
                to: CGPoint(
                    x: 0.95866*width,
                    y: 0.04327*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.88536*width,
                    y: 0.12631*height
                ),
                control1: CGPoint(
                    x: 0.9335*width,
                    y: 0.06519*height
                ),
                control2: CGPoint(
                    x: 0.90832*width,
                    y: 0.08793*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.82372*width,
                    y: 0.25717*height
                ),
                control1: CGPoint(
                    x: 0.86465*width,
                    y: 0.16865*height
                ),
                control2: CGPoint(
                    x: 0.84281*width,
                    y: 0.20779*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.7831*width,
                    y: 0.39192*height
                ),
                control1: CGPoint(
                    x: 0.80909*width,
                    y: 0.29875*height
                ),
                control2: CGPoint(
                    x: 0.79468*width,
                    y: 0.34173*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.76179*width,
                    y: 0.65986*height
                ),
                control1: CGPoint(
                    x: 0.76733*width,
                    y: 0.47264*height
                ),
                control2: CGPoint(
                    x: 0.75099*width,
                    y: 0.56663*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.81405*width,
                    y: 0.82433*height
                ),
                control1: CGPoint(
                    x: 0.77255*width,
                    y: 0.72808*height
                ),
                control2: CGPoint(
                    x: 0.79082*width,
                    y: 0.78838*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.82758*width,
                    y: 0.84945*height
                ),
                control1: CGPoint(
                    x: 0.81849*width,
                    y: 0.83375*height
                ),
                control2: CGPoint(
                    x: 0.82208*width,
                    y: 0.84555*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.86383*width,
                    y: 0.87847*height
                ),
                control1: CGPoint(
                    x: 0.83977*width,
                    y: 0.85963*height
                ),
                control2: CGPoint(
                    x: 0.85055*width,
                    y: 0.88313*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.88703*width,
                    y: 0.84317*height
                ),
                control1: CGPoint(
                    x: 0.8735*width,
                    y: 0.88075*height
                ),
                control2: CGPoint(
                    x: 0.88068*width,
                    y: 0.86039*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.93073*width,
                    y: 0.76251*height
                ),
                control1: CGPoint(
                    x: 0.90365*width,
                    y: 0.82823*height
                ),
                control2: CGPoint(
                    x: 0.91993*width,
                    y: 0.80322*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.95979*width,
                    y: 0.68887*height
                ),
                control1: CGPoint(
                    x: 0.93902*width,
                    y: 0.73348*height
                ),
                control2: CGPoint(
                    x: 0.95009*width,
                    y: 0.71389*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.9725*width,
                    y: 0.6317*height
                ),
                control1: CGPoint(
                    x: 0.96421*width,
                    y: 0.67004*height
                ),
                control2: CGPoint(
                    x: 0.96835*width,
                    y: 0.65119*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.98713*width,
                    y: 0.53842*height
                ),
                control1: CGPoint(
                    x: 0.97556*width,
                    y: 0.59879*height
                ),
                control2: CGPoint(
                    x: 0.97858*width,
                    y: 0.56349*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.99184*width,
                    y: 0.49689*height
                ),
                control1: CGPoint(
                    x: 0.99159*width,
                    y: 0.52749*height
                ),
                control2: CGPoint(
                    x: 0.98578*width,
                    y: 0.50474*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: width,
                    y: 0.47814*height
                ),
                control1: CGPoint(
                    x: 0.99408*width,
                    y: 0.4918*height
                ),
                control2: CGPoint(
                    x: 0.99962*width,
                    y: 0.48723*height
                )
            )
        path
            .addLine(
                to: CGPoint(
                    x: width,
                    y: 0.47619*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.99933*width,
                    y: 0.47107*height
                ),
                control1: CGPoint(
                    x: 0.99994*width,
                    y: 0.47461*height
                ),
                control2: CGPoint(
                    x: 0.99972*width,
                    y: 0.47292*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.98065*width,
                    y: 0.48055*height
                ),
                control1: CGPoint(
                    x: 0.99302*width,
                    y: 0.46872*height
                ),
                control2: CGPoint(
                    x: 0.98687*width,
                    y: 0.47464*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.96115*width,
                    y: 0.48986*height
                ),
                control1: CGPoint(
                    x: 0.97429*width,
                    y: 0.4866*height
                ),
                control2: CGPoint(
                    x: 0.96786*width,
                    y: 0.49265*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.86106*width,
                    y: 0.55331*height
                ),
                control1: CGPoint(
                    x: 0.92909*width,
                    y: 0.52277*height
                ),
                control2: CGPoint(
                    x: 0.89589*width,
                    y: 0.56116*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.85341*width,
                    y: 0.55318*height
                ),
                control1: CGPoint(
                    x: 0.85872*width,
                    y: 0.55236*height
                ),
                control2: CGPoint(
                    x: 0.85608*width,
                    y: 0.55277*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.83756*width,
                    y: 0.53918*height
                ),
                control1: CGPoint(
                    x: 0.84722*width,
                    y: 0.55412*height
                ),
                control2: CGPoint(
                    x: 0.84084*width,
                    y: 0.55506*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.837*width,
                    y: 0.48044*height
                ),
                control1: CGPoint(
                    x: 0.83588*width,
                    y: 0.52039*height
                ),
                control2: CGPoint(
                    x: 0.83452*width,
                    y: 0.50004*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.87017*width,
                    y: 0.34092*height
                ),
                control1: CGPoint(
                    x: 0.84446*width,
                    y: 0.42793*height
                ),
                control2: CGPoint(
                    x: 0.85831*width,
                    y: 0.38564*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.89423*width,
                    y: 0.27596*height
                ),
                control1: CGPoint(
                    x: 0.87683*width,
                    y: 0.31591*height
                ),
                control2: CGPoint(
                    x: 0.88676*width,
                    y: 0.29945*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.96197*width,
                    y: 0.16313*height
                ),
                control1: CGPoint(
                    x: 0.91416*width,
                    y: 0.22663*height
                ),
                control2: CGPoint(
                    x: 0.9396*width,
                    y: 0.20075*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.98825*width,
                    y: 0.11695*height
                ),
                control1: CGPoint(
                    x: 0.97057*width,
                    y: 0.14597*height
                ),
                control2: CGPoint(
                    x: 0.98137*width,
                    y: 0.1412*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.99017*width,
                    y: 0.05891*height
                ),
                control1: CGPoint(
                    x: 0.98991*width,
                    y: 0.09811*height
                ),
                control2: CGPoint(
                    x: 0.98937*width,
                    y: 0.07856*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.97251*width,
                    y: 0.03749*height
                ),
                control1: CGPoint(
                    x: 0.98578*width,
                    y: 0.04276*height
                ),
                control2: CGPoint(
                    x: 0.97927*width,
                    y: 0.03749*height
                )
            )
        path
            .addCurve(
                to: CGPoint(
                    x: 0.95866*width,
                    y: 0.04327*height
                ),
                control1: CGPoint(
                    x: 0.9678*width,
                    y: 0.03749*height
                ),
                control2: CGPoint(
                    x: 0.96298*width,
                    y: 0.04004*height
                )
            )
        
        // Apply offset to center the path
        return path
            .offsetBy(
                dx: offsetX,
                dy: offsetY
            )
    }
}

