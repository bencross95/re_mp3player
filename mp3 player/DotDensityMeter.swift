import SwiftUI

struct DotDensityMeter: View {
    let samples: [CGFloat]

    var dotSize: CGFloat = 2.0
    var minAlpha: CGFloat = 0.12
    var maxAlpha: CGFloat = 0.95
    var boost: CGFloat = 12.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let centerY = h / 2
            let count = max(samples.count, 1)
            let stepX = w / CGFloat(count)

            let sum = samples.reduce(CGFloat.zero, +)
            let avg = sum / CGFloat(count)
            let energy = min(max(avg * boost, 0), 1)

            let onCount = Int((Double(energy) * Double(count)).rounded())

            Canvas { context, _ in
                for i in 0..<count {
                    let x = stepX * (CGFloat(i) + 0.5)

                    let isOn = i < onCount
                    let fade = CGFloat(i) / CGFloat(max(count - 1, 1))

                    let alpha: CGFloat
                    if isOn {
                        alpha = minAlpha + (maxAlpha - minAlpha) * (0.75 + 0.25 * (1 - fade))
                    } else {
                        alpha = minAlpha
                    }

                    context.opacity = Double(alpha)

                    let rect = CGRect(
                        x: x - dotSize / 2,
                        y: centerY - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
    }
}
