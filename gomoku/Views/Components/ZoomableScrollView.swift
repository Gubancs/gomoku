import SwiftUI

/// A zoomable, pannable container backed by UIScrollView.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    @Binding var zoomScale: CGFloat
    let minZoomScale: CGFloat
    let maxZoomScale: CGFloat
    let recenterToken: Int
    let content: Content

    init(
        zoomScale: Binding<CGFloat>,
        minZoomScale: CGFloat,
        maxZoomScale: CGFloat,
        recenterToken: Int,
        @ViewBuilder content: () -> Content
    ) {
        _zoomScale = zoomScale
        self.minZoomScale = minZoomScale
        self.maxZoomScale = maxZoomScale
        self.recenterToken = recenterToken
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minZoomScale
        scrollView.maximumZoomScale = maxZoomScale
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.backgroundColor = .clear

        let hostingController = context.coordinator.hostingController
        guard let hostingView = hostingController.view else {
            return scrollView
        }
        hostingView.backgroundColor = .clear
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostingView)

        let contentLayout = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentLayout.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentLayout.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentLayout.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentLayout.bottomAnchor)
        ])

        let widthConstraint = hostingView.widthAnchor.constraint(equalToConstant: 0)
        let heightConstraint = hostingView.heightAnchor.constraint(equalToConstant: 0)
        widthConstraint.isActive = true
        heightConstraint.isActive = true
        context.coordinator.widthConstraint = widthConstraint
        context.coordinator.heightConstraint = heightConstraint

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let hostingController = context.coordinator.hostingController
        hostingController.rootView = content

        let fittingSize = CGSize(
            width: CGFloat(Double.greatestFiniteMagnitude),
            height: CGFloat(Double.greatestFiniteMagnitude)
        )
        let contentSize = hostingController.sizeThatFits(in: fittingSize)

        if context.coordinator.lastBaseSize != contentSize {
            context.coordinator.lastBaseSize = contentSize
            context.coordinator.widthConstraint?.constant = contentSize.width
            context.coordinator.heightConstraint?.constant = contentSize.height
            scrollView.layoutIfNeeded()
        }

        if !context.coordinator.isZoomingGestureActive,
           abs(scrollView.zoomScale - zoomScale) > 0.0001 {
            scrollView.setZoomScale(zoomScale, animated: false)
        }

        if context.coordinator.lastRecenterToken != recenterToken {
            context.coordinator.lastRecenterToken = recenterToken
            context.coordinator.pendingForcedCenter = true
        }

        let hasValidLayout =
            scrollView.bounds.width > 0
            && scrollView.bounds.height > 0
            && contentSize.width > 0
            && contentSize.height > 0
        let shouldForceCenter = context.coordinator.pendingForcedCenter && hasValidLayout

        context.coordinator.centerContent(in: scrollView, forceOffset: shouldForceCenter)

        if shouldForceCenter {
            context.coordinator.pendingForcedCenter = false
        }
    }

    /// Coordinator to bridge UIScrollView delegate callbacks.
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableScrollView
        let hostingController: UIHostingController<Content>
        var widthConstraint: NSLayoutConstraint?
        var heightConstraint: NSLayoutConstraint?
        var lastRecenterToken: Int = -1
        var lastBaseSize: CGSize = .zero
        var pendingForcedCenter: Bool = true
        var isZoomingGestureActive: Bool = false

        init(_ parent: ZoomableScrollView) {
            self.parent = parent
            self.hostingController = UIHostingController(rootView: parent.content)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isZoomingGestureActive = true
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView, forceOffset: false)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isZoomingGestureActive = false
            if abs(parent.zoomScale - scale) > 0.0001 {
                DispatchQueue.main.async {
                    self.parent.zoomScale = scale
                }
            }
        }

        func centerContent(in scrollView: UIScrollView, forceOffset: Bool) {
            let boundsSize = scrollView.bounds.size
            let contentFrame = hostingController.view.frame
            let insetX = max((boundsSize.width - contentFrame.width) / 2, 0)
            let insetY = max((boundsSize.height - contentFrame.height) / 2, 0)
            let insets = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)

            if scrollView.contentInset != insets {
                scrollView.contentInset = insets
            }

            if forceOffset {
                let targetX = (contentFrame.width - boundsSize.width) / 2
                let targetY = (contentFrame.height - boundsSize.height) / 2
                scrollView.setContentOffset(CGPoint(x: targetX, y: targetY), animated: false)
            }
        }
    }
}
