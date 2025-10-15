import SpriteKit

private enum PhysicsCategory {
    static let player: UInt32 = 1 << 0
    static let ground: UInt32 = 1 << 1
    static let wall: UInt32 = 1 << 2
}

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private let player = SKShapeNode(rectOf: CGSize(width: 28, height: 36), cornerRadius: 6)
    private var pressingLeft = false
    private var pressingRight = false
    private var moveDirection: CGFloat = 0
    private var groundContacts = 0

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(calibratedRed: 0.12, green: 0.14, blue: 0.20, alpha: 1.0)

        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self

        setupEnvironment()
        setupPlayer()
        setupHUD()

        view.preferredFramesPerSecond = 60
        view.showsFPS = false
        view.showsNodeCount = false

        // Delay first-responder assignment until the next run loop tick so the window is ready.
        DispatchQueue.main.async { [weak self] in
            self?.view?.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        handle(keyCode: event.keyCode, isPressed: true)
    }

    override func keyUp(with event: NSEvent) {
        handle(keyCode: event.keyCode, isPressed: false)
    }

    private func handle(keyCode: UInt16, isPressed: Bool) {
        switch keyCode {
        case 123, 0: // Left arrow or A
            pressingLeft = isPressed
        case 124, 2: // Right arrow or D
            pressingRight = isPressed
        case 49: // Space
            if isPressed && groundContacts > 0, let body = player.physicsBody {
                body.applyImpulse(CGVector(dx: 0, dy: 280))
            }
        default:
            break
        }
        updateMoveDirection()
    }

    private func updateMoveDirection() {
        var direction: CGFloat = 0
        if pressingLeft { direction -= 1 }
        if pressingRight { direction += 1 }
        moveDirection = direction
    }

    override func update(_ currentTime: TimeInterval) {
        guard let body = player.physicsBody else { return }
        let maxSpeed: CGFloat = 220
        body.velocity = CGVector(dx: moveDirection * maxSpeed, dy: body.velocity.dy)
    }

    func didBegin(_ contact: SKPhysicsContact) {
        if contact.involvesPlayerAndGround {
            groundContacts += 1
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        if contact.involvesPlayerAndGround {
            groundContacts = max(groundContacts - 1, 0)
        }
    }

    private func setupEnvironment() {
        let ground = SKNode()
        ground.position = CGPoint(x: 0, y: -120)
        ground.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 40))
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(ground)

        let groundVisual = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: 20), cornerRadius: 4)
        groundVisual.fillColor = SKColor(calibratedRed: 0.18, green: 0.21, blue: 0.30, alpha: 1.0)
        groundVisual.strokeColor = .clear
        groundVisual.position = ground.position
        addChild(groundVisual)

        addWall(at: CGPoint(x: -size.width / 2 + 16, y: 0))
        addWall(at: CGPoint(x: size.width / 2 - 16, y: 0))

        addPlatform(width: 120, height: 16, position: CGPoint(x: -100, y: -20))
        addPlatform(width: 140, height: 16, position: CGPoint(x: 120, y: 40))
        addPlatform(width: 100, height: 16, position: CGPoint(x: -40, y: 110))
    }

    private func addWall(at position: CGPoint) {
        let wall = SKNode()
        wall.position = position
        wall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 16, height: size.height))
        wall.physicsBody?.isDynamic = false
        wall.physicsBody?.categoryBitMask = PhysicsCategory.wall
        addChild(wall)
    }

    private func addPlatform(width: CGFloat, height: CGFloat, position: CGPoint) {
        let platform = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 3)
        platform.fillColor = SKColor(calibratedRed: 0.32, green: 0.36, blue: 0.48, alpha: 1.0)
        platform.strokeColor = .clear
        platform.position = position
        platform.zPosition = -1
        platform.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(platform)
    }

    private func setupPlayer() {
        player.fillColor = SKColor(white: 0.95, alpha: 1.0)
        player.strokeColor = .clear
        player.position = CGPoint(x: 0, y: -70)
        player.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 24, height: 34))
        player.physicsBody?.allowsRotation = false
        player.physicsBody?.restitution = 0.0
        player.physicsBody?.friction = 0.3
        player.physicsBody?.categoryBitMask = PhysicsCategory.player
        player.physicsBody?.collisionBitMask = PhysicsCategory.ground | PhysicsCategory.wall
        player.physicsBody?.contactTestBitMask = PhysicsCategory.ground
        addChild(player)
    }

    private func setupHUD() {
        let label = SKLabelNode(text: "←/A move left  •  →/D move right  •  Space jump  •  ⌘Q quit")
        label.fontName = ".AppleSystemUIFont"
        label.fontSize = 12
        label.fontColor = SKColor(white: 0.9, alpha: 0.9)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: 0, y: size.height / 2 - 20)
        addChild(label)
    }
}

private extension SKPhysicsContact {
    var involvesPlayerAndGround: Bool {
        let categories = bodyA.categoryBitMask | bodyB.categoryBitMask
        return (categories & PhysicsCategory.player) != 0 && (categories & PhysicsCategory.ground) != 0
    }
}
