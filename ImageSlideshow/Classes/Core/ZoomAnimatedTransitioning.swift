//
//  ZoomAnimatedTransitioning.swift
//  ImageSlideshow
//
//  Created by Petr Zvoníček on 31.08.15.
//
//

import UIKit

@objcMembers
open class ZoomAnimatedTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    
    private enum SwipeDirection {
        case down, up
    }
    
    /// parent image view used for animated transition
    open var referenceImageView: UIImageView?
    /// parent slideshow view used for animated transition
    open weak var referenceSlideshowView: ImageSlideshow?

    // must be weak because FullScreenSlideshowViewController has strong reference to its transitioning delegate
    weak var referenceSlideshowController: FullScreenSlideshowViewController?

    var referenceSlideshowViewFrame: CGRect?
    var gestureRecognizer: UIPanGestureRecognizer!
    fileprivate var interactionController: UIPercentDrivenInteractiveTransition?

    /// Swipe-to-dismiss interactive transition mode.
    open var dismissMode: FullScreenSlideshowViewController.DismissMode
    
    private var swipeDirection = SwipeDirection.up

    /**
        Init the transitioning delegate with a source ImageSlideshow
        - parameter slideshowView: ImageSlideshow instance to animate the transition from
        - parameter slideshowController: FullScreenViewController instance to animate the transition to
     */
    public init(slideshowView: ImageSlideshow, slideshowController: FullScreenSlideshowViewController, dismissMode: FullScreenSlideshowViewController.DismissMode) {
        self.referenceSlideshowView = slideshowView
        self.referenceSlideshowController = slideshowController
        self.dismissMode = dismissMode

        super.init()

        initialize()
    }

    /**
        Init the transitioning delegate with a source ImageView
        - parameter imageView: UIImageView instance to animate the transition from
        - parameter slideshowController: FullScreenViewController instance to animate the transition to
     */
    public init(imageView: UIImageView, slideshowController: FullScreenSlideshowViewController, dismissMode: FullScreenSlideshowViewController.DismissMode) {
        self.referenceImageView = imageView
        self.referenceSlideshowController = slideshowController
        self.dismissMode = dismissMode

        super.init()

        initialize()
    }

    func initialize() {
        // Pan gesture recognizer for interactive dismiss
        gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(ZoomAnimatedTransitioningDelegate.handleSwipe(_:)))
        gestureRecognizer.delegate = self
        // Append it to a window otherwise it will be canceled during the transition
        UIApplication.shared.keyWindow?.addGestureRecognizer(gestureRecognizer)
    }

    @objc func handleSwipe(_ gesture: UIPanGestureRecognizer) {
        guard let referenceSlideshowController = referenceSlideshowController else { return }
        guard let gestureView = gesture.view else { assertionFailure("Gesture view is `nil`"); return }
        
        let percent: CGFloat
        let velocityY: CGFloat
        let gestureViewYTranslation = gesture.translation(in: gestureView).y
        let referenceSlideshowViewYVelocity = gesture.velocity(in: referenceSlideshowView).y
        switch (dismissMode, swipeDirection) {
        case (.onSwipeUp, _), (.onSwipe, .up):
            percent = min(max(gestureViewYTranslation / -200.0, 0.0), 1.0)
            velocityY = referenceSlideshowViewYVelocity * -1
        case (.onSwipeDown, _), (.onSwipe, .down):
            percent = min(max(gestureViewYTranslation / 200.0, 0.0), 1.0)
            velocityY = referenceSlideshowViewYVelocity
        case (.disabled, _):
            assertionFailure("Swipe should not be initiated in disabled mode")
            percent = 0
            velocityY = 0
        }
        
        switch gesture.state {
        case .began:
            swipeDirection = (gesture.velocity(in: referenceSlideshowView).y > 0) ? .down : .up
            interactionController = UIPercentDrivenInteractiveTransition()
            referenceSlideshowController.dismiss(animated: true, completion: nil)
        case .changed:
            interactionController?.update(percent)
        case .ended, .cancelled, .failed:
            if velocityY > 500 || percent > 0.75 {
                if let pageSelected = referenceSlideshowController.pageSelected {
                    pageSelected(referenceSlideshowController.slideshow.currentPage)
                }
                
                interactionController?.finish()
            } else {
                interactionController?.cancel()
            }
            
            interactionController = nil
        default:
            break
        }
    }

    open func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if let reference = referenceSlideshowView {
            return ZoomInAnimator(referenceSlideshowView: reference, parent: self)
        } else if let reference = referenceImageView {
            return ZoomInAnimator(referenceImageView: reference, parent: self)
        } else {
            return nil
        }
    }

    open func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if let reference = referenceSlideshowView {
            return ZoomOutAnimator(referenceSlideshowView: reference, parent: self)
        } else if let reference = referenceImageView {
            return ZoomOutAnimator(referenceImageView: reference, parent: self)
        } else {
            return nil
        }
    }

    open func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return interactionController
    }

    open func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return interactionController
    }
}

extension ZoomAnimatedTransitioningDelegate: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let gestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else {
            return false
        }

        if dismissMode == .disabled {
            return false
        }

        if let currentItem = referenceSlideshowController?.slideshow.currentSlideshowItem, currentItem.isZoomed() {
            return false
        }

        if let view = gestureRecognizer.view {
            let velocity = gestureRecognizer.velocity(in: view)
            
            switch dismissMode {
            case .onSwipe:
                return fabs(velocity.x) < fabs(velocity.y)
            case .onSwipeUp:
                return fabs(velocity.x) < fabs(velocity.y) && velocity.y < 0
            case .onSwipeDown:
                return fabs(velocity.x) < fabs(velocity.y) && velocity.y > 0
            case .disabled:
                break
            }
        }

        return true
    }
}

@objcMembers
class ZoomAnimator: NSObject {

    var referenceImageView: UIImageView?
    var referenceSlideshowView: ImageSlideshow?
    var parent: ZoomAnimatedTransitioningDelegate

    init(referenceSlideshowView: ImageSlideshow, parent: ZoomAnimatedTransitioningDelegate) {
        self.referenceSlideshowView = referenceSlideshowView
        self.referenceImageView = referenceSlideshowView.currentSlideshowItem?.imageView
        self.parent = parent
        super.init()
    }

    init(referenceImageView: UIImageView, parent: ZoomAnimatedTransitioningDelegate) {
        self.referenceImageView = referenceImageView
        self.parent = parent
        super.init()
    }
}

@objcMembers
class ZoomInAnimator: ZoomAnimator, UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.5
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        // Pauses slideshow
        self.referenceSlideshowView?.pauseTimer()

        let containerView = transitionContext.containerView
        let fromViewController = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.from)!

        guard let toViewController = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.to) as? FullScreenSlideshowViewController else {
            return
        }

        toViewController.view.frame = transitionContext.finalFrame(for: toViewController)

        let transitionBackgroundView = UIView(frame: containerView.frame)
        transitionBackgroundView.backgroundColor = toViewController.backgroundColor
        containerView.addSubview(transitionBackgroundView)
        containerView.sendSubview(toBack: transitionBackgroundView)

        let finalFrame = toViewController.view.frame

        var transitionView: UIImageView?
        var transitionViewFinalFrame = finalFrame
        if let referenceImageView = referenceImageView {
            transitionView = UIImageView(image: referenceImageView.image)
            transitionView!.contentMode = UIViewContentMode.scaleAspectFill
            transitionView!.clipsToBounds = true
            transitionView!.frame = containerView.convert(referenceImageView.bounds, from: referenceImageView)
            containerView.addSubview(transitionView!)
            self.parent.referenceSlideshowViewFrame = transitionView!.frame

            referenceImageView.alpha = 0

            if let image = referenceImageView.image {
                transitionViewFinalFrame = image.tgr_aspectFitRectForSize(finalFrame.size)
            }
        }

        if let item = toViewController.slideshow.currentSlideshowItem, item.zoomInInitially {
            transitionViewFinalFrame.size = CGSize(width: transitionViewFinalFrame.size.width * item.maximumZoomScale, height: transitionViewFinalFrame.size.height * item.maximumZoomScale)
        }

        let duration: TimeInterval = transitionDuration(using: transitionContext)

        UIView.animate(withDuration: duration, delay:0, usingSpringWithDamping:0.7, initialSpringVelocity:0, options: UIViewAnimationOptions.curveLinear, animations: {
            fromViewController.view.alpha = 0
            transitionView?.frame = transitionViewFinalFrame
            transitionView?.center = CGPoint(x: finalFrame.midX, y: finalFrame.midY)
        }, completion: {[ref = self.referenceImageView] _ in
            fromViewController.view.alpha = 1
            ref?.alpha = 1
            transitionView?.removeFromSuperview()
            transitionBackgroundView.removeFromSuperview()
            containerView.addSubview(toViewController.view)
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        })
    }
}

class ZoomOutAnimator: ZoomAnimator, UIViewControllerAnimatedTransitioning {

    private var animatorForCurrentTransition: UIViewImplicitlyAnimating?

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.25
    }

    @available(iOS 10.0, *)
    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        // as per documentation, the same object should be returned for the ongoing transition
        if let animatorForCurrentSession = animatorForCurrentTransition {
            return animatorForCurrentSession
        }
        
        let params = animationParams(using: transitionContext)

        let animator = UIViewPropertyAnimator(duration: params.0, curve: .linear, animations: params.1)
        animator.addCompletion(params.2)
        animatorForCurrentTransition = animator

        return animator
    }

    private func animationParams(using transitionContext: UIViewControllerContextTransitioning) -> (TimeInterval, () -> (), (Any) -> ()) {
        let toViewController: UIViewController = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.to)!

        guard let fromViewController = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.from) as? FullScreenSlideshowViewController else {
            fatalError("Transition not used with FullScreenSlideshowViewController")
        }

        let containerView = transitionContext.containerView

        toViewController.view.frame = transitionContext.finalFrame(for: toViewController)
        toViewController.view.alpha = 0
        containerView.addSubview(toViewController.view)
        containerView.sendSubview(toBack: toViewController.view)

        var transitionViewInitialFrame: CGRect
        if let currentSlideshowItem = fromViewController.slideshow.currentSlideshowItem {
            if let image = currentSlideshowItem.imageView.image {
                transitionViewInitialFrame = image.tgr_aspectFitRectForSize(currentSlideshowItem.imageView.frame.size)
            } else {
                transitionViewInitialFrame = currentSlideshowItem.imageView.frame
            }
            transitionViewInitialFrame = containerView.convert(transitionViewInitialFrame, from: currentSlideshowItem)
        } else {
            transitionViewInitialFrame = fromViewController.slideshow.frame
        }

        var transitionViewFinalFrame: CGRect
        if let referenceImageView = referenceImageView {
            referenceImageView.alpha = 0

            let referenceSlideshowViewFrame = containerView.convert(referenceImageView.bounds, from: referenceImageView)
            transitionViewFinalFrame = referenceSlideshowViewFrame

            // do a frame scaling when AspectFit content mode enabled
            if fromViewController.slideshow.currentSlideshowItem?.imageView.image != nil && referenceImageView.contentMode == UIViewContentMode.scaleAspectFit {
                transitionViewFinalFrame = containerView.convert(referenceImageView.aspectToFitFrame(), from: referenceImageView)
            }

            // fixes the problem when the referenceSlideshowViewFrame was shifted during change of the status bar hidden state
            if UIApplication.shared.isStatusBarHidden && !toViewController.prefersStatusBarHidden && referenceSlideshowViewFrame.origin.y != parent.referenceSlideshowViewFrame?.origin.y {
                transitionViewFinalFrame = transitionViewFinalFrame.offsetBy(dx: 0, dy: 20)
            }
        } else {
            transitionViewFinalFrame = referenceSlideshowView?.frame ?? CGRect.zero
        }

        let transitionBackgroundView = UIView(frame: containerView.frame)
        transitionBackgroundView.backgroundColor = fromViewController.backgroundColor
        containerView.addSubview(transitionBackgroundView)
        containerView.sendSubview(toBack: transitionBackgroundView)

        let transitionView: UIImageView = UIImageView(image: fromViewController.slideshow.currentSlideshowItem?.imageView.image)
        transitionView.contentMode = UIViewContentMode.scaleAspectFill
        transitionView.clipsToBounds = true
        transitionView.frame = transitionViewInitialFrame
        containerView.addSubview(transitionView)
        fromViewController.view.isHidden = true

        let duration: TimeInterval = transitionDuration(using: transitionContext)
        let animations = {
            toViewController.view.alpha = 1
            transitionView.frame = transitionViewFinalFrame
        }
        let completion = { (_: Any) in
            let completed = !transitionContext.transitionWasCancelled
            self.referenceImageView?.alpha = 1

            if completed {
                fromViewController.view.removeFromSuperview()
                UIApplication.shared.keyWindow?.removeGestureRecognizer(self.parent.gestureRecognizer)
                // Unpauses slideshow
                self.referenceSlideshowView?.unpauseTimer()
            } else {
                fromViewController.view.isHidden = false
            }

            transitionView.removeFromSuperview()
            transitionBackgroundView.removeFromSuperview()

            self.animatorForCurrentTransition = nil

            transitionContext.completeTransition(completed)
        }

        return (duration, animations, completion)
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        // Working around iOS 10+ breaking change requiring to use UIPropertyAnimator for proper interactive transition instead of UIView.animate
        if #available(iOS 10.0, *) {
            interruptibleAnimator(using: transitionContext).startAnimation()
        } else {
            let params = animationParams(using: transitionContext)
            UIView.animate(withDuration: params.0, delay: 0, options: UIViewAnimationOptions(), animations: params.1, completion: params.2)
        }
    }
}
