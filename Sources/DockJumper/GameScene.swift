import Foundation
import SpriteKit

private enum PhysicsCategory {
    static let player: UInt32 = 1 << 0
    static let ground: UInt32 = 1 << 1
    static let wall: UInt32 = 1 << 2
    static let hazard: UInt32 = 1 << 3
}

private enum MovementTuning {
    static let moveSpeed: CGFloat = 165
    static let groundAcceleration: CGFloat = 0.28
    static let airAcceleration: CGFloat = 0.12
    static let jumpImpulse: CGFloat = 350
    static let maxRiseSpeed: CGFloat = 350
    static let maxFallSpeed: CGFloat = -260
    static let gravity: CGFloat = -2.9
}

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private let player = SKShapeNode(rectOf: CGSize(width: 28, height: 36), cornerRadius: 6)
    private let cameraNode = SKCameraNode()
    private var hudLabel: SKLabelNode?
    private var scoreLabel: SKLabelNode?

    private var pressingLeft = false
    private var pressingRight = false
    private var moveDirection: CGFloat = 0
    private var groundContacts = 0

    private var platformNodes: [SKNode] = []
    private var nextPlatformY: CGFloat = 140
    private let platformSpawnMargin: CGFloat = 220
    private let platformCleanupMargin: CGFloat = 300
    private var currentScore = 0
    private var highScore = UserDefaults.standard.integer(forKey: "DockJumperHighScore")
    private var platformsCreated = 0
    private weak var movingPlatformUnderPlayer: SKNode?
    private var movingPlatformLastX: CGFloat = 0

    private var killZone: SKNode?

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(calibratedRed: 0.12, green: 0.14, blue: 0.20, alpha: 1.0)

        physicsWorld.gravity = CGVector(dx: 0, dy: MovementTuning.gravity)
        physicsWorld.contactDelegate = self

        addChild(cameraNode)
        camera = cameraNode

        setupEnvironment()
        setupPlayer()
        setupHUD()
        setupKillZone()
        extendPlatformsIfNeeded(force: true)
        updateCameraPosition()
        updateKillZonePosition()
        updateScoreLabel()

        view.preferredFramesPerSecond = 60
        view.showsFPS = false
        view.showsNodeCount = false

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
        case 123, 0: pressingLeft = isPressed
        case 124, 2: pressingRight = isPressed
        case 49:
            if isPressed && groundContacts > 0, let body = player.physicsBody {
                var velocity = body.velocity
                if velocity.dy < 0 { velocity.dy = 0 }
                body.velocity = velocity
                body.applyImpulse(CGVector(dx: 0, dy: MovementTuning.jumpImpulse))
                if body.velocity.dy > MovementTuning.maxRiseSpeed {
                    body.velocity.dy = MovementTuning.maxRiseSpeed
                }
                movingPlatformUnderPlayer = nil
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
        applyHorizontalControl()
        extendPlatformsIfNeeded()
        cleanupPlatforms()
        updateCameraPosition()
        updateKillZonePosition()
        checkPlatformScoring()
        enforceBounds()
    }

    override func didSimulatePhysics() {
        super.didSimulatePhysics()
        syncPlayerWithMovingPlatform()
    }

    private func applyHorizontalControl() {
        guard let body = player.physicsBody else { return }

        var velocity = body.velocity
        let targetVx = moveDirection * MovementTuning.moveSpeed
        let accel =
            groundContacts > 0
            ? MovementTuning.groundAcceleration
            : MovementTuning.airAcceleration
        velocity.dx += (targetVx - velocity.dx) * accel
        let limit = MovementTuning.moveSpeed
        velocity.dx = max(min(velocity.dx, limit), -limit)
        if velocity.dy < MovementTuning.maxFallSpeed {
            velocity.dy = MovementTuning.maxFallSpeed
        }
        body.velocity = velocity
    }

    func didBegin(_ contact: SKPhysicsContact) {
        if contact.involvesPlayerAndGround {
            groundContacts += 1
            if let movingPlatform = movingPlatform(from: contact) {
                movingPlatformUnderPlayer = movingPlatform
                movingPlatformLastX = movingPlatform.position.x
            }
        }
        if contact.involvesPlayerAndHazard { respawn() }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        if contact.involvesPlayerAndGround {
            groundContacts = max(groundContacts - 1, 0)
            if let movingPlatform = movingPlatform(from: contact),
                movingPlatform === movingPlatformUnderPlayer
            {
                movingPlatformUnderPlayer = nil
                movingPlatformLastX = 0
            }
            if groundContacts == 0 {
                movingPlatformUnderPlayer = nil
                movingPlatformLastX = 0
            }
        }
    }

    private func setupEnvironment() {
        let ground = SKNode()
        ground.position = CGPoint(x: 0, y: -140)
        ground.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 60))
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = PhysicsCategory.ground
        addChild(ground)

        let groundShape = SKShapeNode(
            rectOf: CGSize(width: size.width * 2, height: 40), cornerRadius: 4)
        groundShape.fillColor = SKColor(calibratedRed: 0.18, green: 0.21, blue: 0.30, alpha: 1.0)
        groundShape.strokeColor = .clear
        groundShape.position = ground.position
        groundShape.zPosition = -1
        addChild(groundShape)

        addWall(at: CGPoint(x: -size.width / 2 + 16, y: 0))
        addWall(at: CGPoint(x: size.width / 2 - 16, y: 0))

        buildStartingPlatforms()
    }

    private func addWall(at position: CGPoint) {
        let wall = SKNode()
        wall.position = position
        wall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 16, height: size.height * 4))
        wall.physicsBody?.isDynamic = false
        wall.physicsBody?.categoryBitMask = PhysicsCategory.wall
        addChild(wall)
    }

    private func buildStartingPlatforms() {
        platformNodes.forEach { $0.removeFromParent() }
        platformNodes.removeAll()
        platformsCreated = 0

        addPlatform(width: 140, height: 16, position: CGPoint(x: -100, y: -20))
        addPlatform(width: 140, height: 16, position: CGPoint(x: 120, y: 40))
        addPlatform(width: 110, height: 16, position: CGPoint(x: -40, y: 110))

        nextPlatformY =
            (platformNodes.map(\.position.y).max() ?? 140) + CGFloat.random(in: 90...130)
    }

    private func setupPlayer() {
        player.fillColor = SKColor(white: 0.95, alpha: 1.0)
        player.strokeColor = .clear
        player.position = CGPoint(x: 0, y: -90)
        player.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 24, height: 34))
        player.physicsBody?.allowsRotation = false
        player.physicsBody?.restitution = 0.0
        player.physicsBody?.friction = 0.3
        player.physicsBody?.linearDamping = 0.2
        player.physicsBody?.categoryBitMask = PhysicsCategory.player
        player.physicsBody?.collisionBitMask = PhysicsCategory.ground | PhysicsCategory.wall
        player.physicsBody?.contactTestBitMask = PhysicsCategory.ground | PhysicsCategory.hazard
        addChild(player)

        cameraNode.position = player.position
        cameraNode.setScale(1.0)
    }

    private func setupHUD() {
        let label = SKLabelNode(text: "←/A move left  •  →/D move right  •  Space jump  •  ⌘Q quit")
        label.fontName = ".AppleSystemUIFont"
        label.fontSize = 12
        label.fontColor = SKColor(white: 0.9, alpha: 0.9)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: 0, y: size.height / 2 - 20)
        cameraNode.addChild(label)
        hudLabel = label

        let score = SKLabelNode(fontNamed: ".AppleSystemUIFont")
        score.fontSize = 14
        score.fontColor = SKColor(white: 0.95, alpha: 1.0)
        score.horizontalAlignmentMode = .left
        score.verticalAlignmentMode = .bottom
        score.position = CGPoint(x: -size.width / 2 + 20, y: -size.height / 2 + 20)
        cameraNode.addChild(score)
        scoreLabel = score
    }

    private func setupKillZone() {
        let hazard = SKNode()
        hazard.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 20))
        hazard.physicsBody?.isDynamic = false
        hazard.physicsBody?.categoryBitMask = PhysicsCategory.hazard
        hazard.physicsBody?.contactTestBitMask = PhysicsCategory.player
        hazard.physicsBody?.collisionBitMask = 0
        addChild(hazard)
        killZone = hazard
    }

    @discardableResult
    private func addPlatform(width: CGFloat, height: CGFloat, position: CGPoint) -> SKNode {
        let platform = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 3)
        platform.fillColor = SKColor(calibratedRed: 0.32, green: 0.36, blue: 0.48, alpha: 1.0)
        platform.strokeColor = .clear
        platform.position = position
        platform.zPosition = -1
        platform.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        let metadata = platform.userData ?? NSMutableDictionary()
        metadata["scored"] = false
        metadata["moving"] = false
        platform.userData = metadata
        platformsCreated += 1
        if platformsCreated % 5 == 0 {
            startOscillation(for: platform, width: width)
            platform.userData?["moving"] = true
        } else {
            platform.removeAllActions()
        }
        addChild(platform)
        platformNodes.append(platform)
        return platform
    }

    private func spawnPlatform(atY y: CGFloat) {
        let width = CGFloat.random(in: 90...150)
        let height: CGFloat = 16
        let halfWidth = width / 2
        let horizontalMargin: CGFloat = 40
        let minX = (-size.width / 2 + halfWidth + horizontalMargin)
        let maxX = (size.width / 2 - halfWidth - horizontalMargin)
        let x = CGFloat.random(in: minX...maxX)
        addPlatform(width: width, height: height, position: CGPoint(x: x, y: y))
    }

    private func startOscillation(for platform: SKNode, width: CGFloat) {
        let halfWidth = width / 2
        let padding: CGFloat = 24
        let travel: CGFloat = 100
        let minX = -size.width / 2 + halfWidth + padding
        let maxX = size.width / 2 - halfWidth - padding
        let proposedLeft = platform.position.x - travel
        let proposedRight = platform.position.x + travel
        let leftTarget = max(minX, proposedLeft)
        let rightTarget = min(maxX, proposedRight)
        if rightTarget - leftTarget < 12 {
            return
        }

        let speed: CGFloat = 80
        let duration: (CGFloat) -> TimeInterval = { distance in
            TimeInterval(max(0.9, distance / speed))
        }

        let toLeftInitial = SKAction.moveTo(
            x: leftTarget, duration: duration(abs(platform.position.x - leftTarget)))
        let toRightInitial = SKAction.moveTo(
            x: rightTarget, duration: duration(abs(rightTarget - platform.position.x)))
        let toRightFull = SKAction.moveTo(
            x: rightTarget, duration: duration(abs(rightTarget - leftTarget)))
        let toLeftFull = SKAction.moveTo(
            x: leftTarget, duration: duration(abs(rightTarget - leftTarget)))

        platform.removeAllActions()
        if Bool.random() {
            let initial = SKAction.sequence([toLeftInitial, toRightFull])
            let loop = SKAction.sequence([toLeftFull, toRightFull])
            platform.run(
                SKAction.sequence([initial, SKAction.repeatForever(loop)]), withKey: "oscillate")
        } else {
            let initial = SKAction.sequence([toRightInitial, toLeftFull])
            let loop = SKAction.sequence([toRightFull, toLeftFull])
            platform.run(
                SKAction.sequence([initial, SKAction.repeatForever(loop)]), withKey: "oscillate")
        }
    }

    private func extendPlatformsIfNeeded(force: Bool = false) {
        let targetY = player.position.y + platformSpawnMargin
        while force || nextPlatformY < targetY {
            spawnPlatform(atY: nextPlatformY)
            nextPlatformY += CGFloat.random(in: 90...130)
            if !force { continue }
            if nextPlatformY >= targetY { break }
        }
    }

    private func cleanupPlatforms() {
        let cutoff = cameraNode.position.y - platformCleanupMargin
        platformNodes.removeAll { platform in
            guard platform.parent != nil else { return true }
            if platform.position.y < cutoff {
                platform.removeFromParent()
                return true
            }
            return false
        }
    }

    private func updateCameraPosition() {
        let targetY = player.position.y
        let lerp: CGFloat = 0.18
        cameraNode.position.y += (targetY - cameraNode.position.y) * lerp
        cameraNode.position.x = 0
    }

    private func updateKillZonePosition() {
        guard let hazard = killZone else { return }
        hazard.position = CGPoint(x: 0, y: cameraNode.position.y - size.height / 2 - 60)
    }

    private func enforceBounds() {
        if let hazardY = killZone?.position.y, player.position.y < hazardY {
            respawn()
        }
    }

    private func syncPlayerWithMovingPlatform() {
        guard groundContacts > 0 else {
            movingPlatformUnderPlayer = nil
            return
        }
        guard let platform = movingPlatformUnderPlayer else { return }
        guard platform.parent != nil else {
            movingPlatformUnderPlayer = nil
            return
        }

        guard let body = player.physicsBody else { return }
        if abs(body.velocity.dy) > 40 {
            movingPlatformUnderPlayer = nil
            movingPlatformLastX = platform.position.x
            return
        }

        let dx = platform.position.x - movingPlatformLastX
        if abs(dx) > .ulpOfOne {
            player.position.x += dx
        }
        movingPlatformLastX = platform.position.x
    }

    private func checkPlatformScoring() {
        for platform in platformNodes {
            guard platform.parent != nil else { continue }
            let alreadyScored = platform.userData?["scored"] as? Bool ?? false
            if alreadyScored { continue }
            if player.position.y > platform.position.y + 8 {
                platform.userData?["scored"] = true
                awardPoint()
            }
        }
    }

    private func awardPoint() {
        currentScore += 1
        if currentScore > highScore {
            highScore = currentScore
            UserDefaults.standard.set(highScore, forKey: "DockJumperHighScore")
        }
        updateScoreLabel()
    }

    private func updateScoreLabel() {
        scoreLabel?.text = "Score: \(currentScore)  High: \(highScore)"
    }

    private func respawn() {
        pressingLeft = false
        pressingRight = false
        moveDirection = 0
        groundContacts = 0
        currentScore = 0
        updateScoreLabel()
        platformsCreated = 0
        movingPlatformUnderPlayer = nil
        movingPlatformLastX = 0

        platformNodes.forEach { $0.removeFromParent() }
        platformNodes.removeAll()
        buildStartingPlatforms()

        player.position = CGPoint(x: 0, y: -90)
        player.physicsBody?.velocity = .zero

        cameraNode.position = player.position
        nextPlatformY =
            (platformNodes.map(\.position.y).max() ?? 140) + CGFloat.random(in: 90...130)
        extendPlatformsIfNeeded(force: true)
        updateKillZonePosition()
    }

    private func movingPlatform(from contact: SKPhysicsContact) -> SKNode? {
        if let node = contact.bodyA.node, node !== player,
            node.userData?["moving"] as? Bool == true
        {
            return node
        }
        if let node = contact.bodyB.node, node !== player,
            node.userData?["moving"] as? Bool == true
        {
            return node
        }
        return nil
    }
}

extension SKPhysicsContact {
    fileprivate var involvesPlayerAndGround: Bool {
        let mask = bodyA.categoryBitMask | bodyB.categoryBitMask
        return (mask & PhysicsCategory.player) != 0 && (mask & PhysicsCategory.ground) != 0
    }

    fileprivate var involvesPlayerAndHazard: Bool {
        let mask = bodyA.categoryBitMask | bodyB.categoryBitMask
        return (mask & PhysicsCategory.player) != 0 && (mask & PhysicsCategory.hazard) != 0
    }
}
