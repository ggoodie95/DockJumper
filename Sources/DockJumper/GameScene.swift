import AppKit
import Foundation
import SpriteKit

import class Foundation.Bundle

private enum Palette {
    static let background = SKColor(calibratedRed: 0.24, green: 0.31, blue: 0.52, alpha: 1.0)
    static let skyline = SKColor(calibratedRed: 0.32, green: 0.41, blue: 0.63, alpha: 1.0)
    static let platform = SKColor(calibratedRed: 0.55, green: 0.64, blue: 0.86, alpha: 1.0)
    static let movingPlatform = SKColor(calibratedRed: 0.68, green: 0.76, blue: 0.94, alpha: 1.0)
    static let hudText = SKColor(calibratedRed: 0.94, green: 0.97, blue: 1.0, alpha: 0.95)
    static let scoreText = SKColor(calibratedRed: 1.0, green: 0.91, blue: 0.72, alpha: 1.0)
}

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
    static let gravity: CGFloat = -3.2
}

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private enum PersistKeys {
        static let highScore = "DockJumperHighScore"
        static let scoreboard = "DockJumperScoreboard"
        static let playerName = "DockJumperPlayerName"
    }

    private struct ScoreEntry: Codable {
        let name: String
        let score: Int
        let date: Date
    }

    private let onlineScoreCapacity = 10
    private let storedScoreLimit = 10
    private var scoreboardEntries: [ScoreEntry] = []
    private var onlineScoreLabels: [SKLabelNode] = []
    private var playerLabel: SKLabelNode?
    private let cloudLayer = SKNode()
    private var nextCloudSpawnY: CGFloat = 120
    private let supportLink = URL(string: "https://buymeacoffee.com/ggoodie95")
    private var playerName: String = "Player" {
        didSet { updatePlayerLabel() }
    }
    private var player = SKSpriteNode()
    private var playerBaseScale: CGFloat = 1
    private lazy var assetBundle: Bundle = {
        #if SWIFT_PACKAGE
            let bundleName = "DockJumper_DockJumper"
            let candidates = [
                Bundle.main.resourceURL,
                Bundle(for: GameScene.self).resourceURL,
                Bundle.main.bundleURL,
            ]
            for candidate in candidates {
                if let bundleURL = candidate?.appendingPathComponent("\(bundleName).bundle"),
                    let bundle = Bundle(url: bundleURL)
                {
                    return bundle
                }
            }
        #endif
        return Bundle.main
    }()
    private lazy var reaperTexture: SKTexture = {
        if let url = assetBundle.url(forResource: "ggoodie951", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            let texture = SKTexture(image: image)
            texture.filteringMode = .nearest
            return texture
        }
        let fallback = SKTexture(imageNamed: "ggoodie951")
        fallback.filteringMode = .nearest
        return fallback
    }()
    private let cameraNode = SKCameraNode()
    private var hudLabel: SKLabelNode?
    private var scoreLabel: SKLabelNode?
    private var introHUDNodes: [SKNode] = []
    private var introHUDVisible = true

    private var pressingLeft = false
    private var pressingRight = false
    private var moveDirection: CGFloat = 0
    private var groundContacts = 0

    private var platformNodes: [SKNode] = []
    private var nextPlatformY: CGFloat = 140
    private let platformSpawnMargin: CGFloat = 220
    private let platformCleanupMargin: CGFloat = 300
    private var currentScore = 0
    private var highScore = 0
    private var platformsCreated = 0
    private weak var movingPlatformUnderPlayer: SKNode?
    private var movingPlatformLastPosition: CGPoint = .zero
    private var lastGroundContactTime: TimeInterval = 0

    private var killZone: SKNode?

    override func didMove(to view: SKView) {
        loadPersistentData()
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = Palette.background

        physicsWorld.gravity = CGVector(dx: 0, dy: MovementTuning.gravity)
        physicsWorld.contactDelegate = self

        addChild(cameraNode)
        camera = cameraNode

        cloudLayer.zPosition = -5
        cloudLayer.removeAllChildren()
        addChild(cloudLayer)

        setupEnvironment()
        setupPlayer()
        setupHUD()
        setupKillZone()
        nextCloudSpawnY = player.position.y + 140
        spawnClouds(upToY: player.position.y + size.height)
        extendPlatformsIfNeeded(force: true)
        updateCameraPosition()
        updateKillZonePosition()
        updateScoreLabel()
        updateScoreboardDisplay()
        updatePlayerLabel()

        view.preferredFramesPerSecond = 60
        view.showsFPS = false
        view.showsNodeCount = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.view?.window?.makeFirstResponder(self)
            self.promptForPlayerNameIfNeeded()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 15 { // R key
            respawn()
        } else {
            handle(keyCode: event.keyCode, isPressed: true)
        }
    }

    override func keyUp(with event: NSEvent) {
        handle(keyCode: event.keyCode, isPressed: false)
    }

    override func mouseUp(with event: NSEvent) {
        let location = event.location(in: self)
        let tappedNodes = nodes(at: location)
        if tappedNodes.contains(where: { $0.name == "support-link" }) {
            openSupportLink()
        }
        super.mouseUp(with: event)
    }

    private func handle(keyCode: UInt16, isPressed: Bool) {
        switch keyCode {
        case 123, 0:
            pressingLeft = isPressed
            if isPressed { hideIntroHUDForRunIfNeeded() }
        case 124, 2:
            pressingRight = isPressed
            if isPressed { hideIntroHUDForRunIfNeeded() }
        case 49:
            if isPressed {
                hideIntroHUDForRunIfNeeded()
            }
            if isPressed, let body = player.physicsBody {
                let canJump =
                    groundContacts > 0
                    || body.velocity.dy > -30 && abs(body.velocity.dx) > 10
                        && timeSinceLastJump() > 0.08
                guard canJump else { break }
                registerJump()
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

    private var lastJumpTime: TimeInterval = 0
    private func registerJump() {
        lastJumpTime = CACurrentMediaTime()
    }

    private func timeSinceLastJump() -> TimeInterval {
        CACurrentMediaTime() - lastJumpTime
    }

    private func updateMoveDirection() {
        var direction: CGFloat = 0
        if pressingLeft { direction -= 1 }
        if pressingRight { direction += 1 }
        moveDirection = direction
        let base = abs(playerBaseScale == 0 ? 1 : playerBaseScale)
        if moveDirection > 0.1 {
            player.xScale = base
        } else if moveDirection < -0.1 {
            player.xScale = -base
        }
    }

    override func update(_ currentTime: TimeInterval) {
        applyHorizontalControl()
        extendPlatformsIfNeeded()
        cleanupPlatforms()
        cleanupClouds()
        updateCameraPosition()
        updateKillZonePosition()
        spawnClouds(upToY: cameraNode.position.y + size.height)
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
            lastGroundContactTime = CACurrentMediaTime()
            if let movingPlatform = movingPlatform(from: contact) {
                movingPlatformUnderPlayer = movingPlatform
                movingPlatformLastPosition = movingPlatform.position
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
                movingPlatformLastPosition = movingPlatform.position
            }
            if groundContacts == 0 {
                lastGroundContactTime = CACurrentMediaTime()
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
        groundShape.fillColor = Palette.skyline
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
        let texture = reaperTexture

        let baseHeight: CGFloat = 100
        let aspect = texture.size().width > 0 ? texture.size().width / texture.size().height : 0.8
        let spriteSize = CGSize(width: baseHeight * aspect, height: baseHeight)

        player.removeAllActions()
        player.removeFromParent()

        player = SKSpriteNode(texture: texture, color: .white, size: spriteSize)
        player.name = "player"
        player.zPosition = 10
        player.position = CGPoint(x: 0, y: -90)
        player.xScale = 1
        player.yScale = 1
        playerBaseScale = 1

        let body: SKPhysicsBody
        if texture.size() != .zero {
            body = SKPhysicsBody(texture: texture, size: spriteSize)
        } else {
            body = SKPhysicsBody(rectangleOf: CGSize(width: 24, height: 34))
        }
        body.allowsRotation = false
        body.restitution = 0.0
        body.friction = 0.6
        body.linearDamping = 0.22
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.ground | PhysicsCategory.wall
        body.contactTestBitMask = PhysicsCategory.ground | PhysicsCategory.hazard
        player.physicsBody = body

        addChild(player)

        cameraNode.position = player.position
        cameraNode.setScale(1.0)

        player.removeAction(forKey: "idle-tilt")
        player.removeAction(forKey: "idle-scale")
        let swayLeft = SKAction.rotate(toAngle: -0.05, duration: 0.45)
        swayLeft.timingMode = .easeInEaseOut
        let swayRight = SKAction.rotate(toAngle: 0.05, duration: 0.45)
        swayRight.timingMode = .easeInEaseOut
        player.run(
            SKAction.repeatForever(SKAction.sequence([swayLeft, swayRight])), withKey: "idle-tilt")

        let scaleUp = SKAction.scaleY(to: 1.06, duration: 0.55)
        scaleUp.timingMode = .easeInEaseOut
        let scaleDown = SKAction.scaleY(to: 0.94, duration: 0.55)
        scaleDown.timingMode = .easeInEaseOut
        player.run(
            SKAction.repeatForever(SKAction.sequence([scaleUp, scaleDown])), withKey: "idle-scale")
    }

    private func setupHUD() {
        let label = SKLabelNode(text: "←/A move left • →/D move right • Space jump • R restart • ⌘Q quit")
        label.fontName = ".AppleSystemUIFont"
        label.fontSize = 12
        label.fontColor = Palette.hudText
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: 0, y: size.height / 2 - 20)
        cameraNode.addChild(label)
        hudLabel = label

        let score = SKLabelNode(fontNamed: ".AppleSystemUIFont")
        score.fontSize = 14
        score.fontColor = Palette.scoreText
        score.horizontalAlignmentMode = .left
        score.verticalAlignmentMode = .bottom
        score.position = CGPoint(x: -size.width / 2 + 20, y: -size.height / 2 + 20)
        cameraNode.addChild(score)
        scoreLabel = score

        let supportCardWidth: CGFloat = 220
        let supportCardHeight: CGFloat = 120
        let supportCard = SKShapeNode(
            rectOf: CGSize(width: supportCardWidth, height: supportCardHeight), cornerRadius: 16)
        supportCard.fillColor = SKColor(calibratedWhite: 1.0, alpha: 0.08)
        supportCard.strokeColor = SKColor(calibratedWhite: 1.0, alpha: 0.18)
        supportCard.lineWidth = 1
        let supportAnchorX = size.width / 2 - supportCardWidth / 2 - 18
        let supportAnchorY = -size.height / 2 + supportCardHeight / 2 + 18
        supportCard.position = CGPoint(x: supportAnchorX, y: supportAnchorY)
        cameraNode.addChild(supportCard)
        registerIntroNode(supportCard)

        let supportTitle = SKLabelNode(fontNamed: ".AppleSystemUIFont")
        supportTitle.fontSize = 13
        supportTitle.fontColor = Palette.scoreText
        supportTitle.horizontalAlignmentMode = .left
        supportTitle.verticalAlignmentMode = .top
        supportTitle.position = CGPoint(
            x: -supportCardWidth / 2 + 16,
            y: supportCardHeight / 2 - 16
        )
        supportTitle.text = "Support the Reaper"
        supportTitle.name = "support-link"
        supportCard.addChild(supportTitle)

        let supportSubtitle = SKLabelNode(fontNamed: ".AppleSystemUIFont")
        supportSubtitle.fontSize = 11
        supportSubtitle.fontColor = Palette.hudText.withAlphaComponent(0.78)
        supportSubtitle.horizontalAlignmentMode = .left
        supportSubtitle.verticalAlignmentMode = .top
        supportSubtitle.position = CGPoint(
            x: supportTitle.position.x,
            y: supportTitle.position.y - 18
        )
        supportSubtitle.text = "Buy DockJumper a coffee to fuel new updates."
        supportSubtitle.name = "support-link"
        supportCard.addChild(supportSubtitle)

        let buttonWidth: CGFloat = supportCardWidth - 28
        let buttonHeight: CGFloat = 32
        let buttonNode = SKShapeNode(
            rectOf: CGSize(width: buttonWidth, height: buttonHeight), cornerRadius: 12)
        buttonNode.fillColor = SKColor(calibratedRed: 0.98, green: 0.82, blue: 0.3, alpha: 0.94)
        buttonNode.strokeColor = SKColor(calibratedRed: 0.82, green: 0.6, blue: 0.18, alpha: 0.85)
        buttonNode.position = CGPoint(x: 0, y: supportSubtitle.position.y - 32)
        buttonNode.name = "support-link"
        supportCard.addChild(buttonNode)

        let cupIcon = SKLabelNode(fontNamed: ".AppleSystemUIFont")
        cupIcon.fontSize = 15
        cupIcon.fontColor = SKColor(calibratedRed: 0.25, green: 0.17, blue: 0.09, alpha: 1.0)
        cupIcon.horizontalAlignmentMode = .center
        cupIcon.verticalAlignmentMode = .center
        cupIcon.text = "☕"
        cupIcon.position = CGPoint(x: -buttonWidth / 2 + 18, y: -2)
        cupIcon.name = "support-link"
        buttonNode.addChild(cupIcon)

        let buttonLabel = SKLabelNode(fontNamed: ".AppleSystemUIFont")
        buttonLabel.fontSize = 12.5
        buttonLabel.fontColor = cupIcon.fontColor
        buttonLabel.horizontalAlignmentMode = .left
        buttonLabel.verticalAlignmentMode = .center
        buttonLabel.text = "Buy Me a Coffee"
        buttonLabel.position = CGPoint(x: -buttonWidth / 2 + 34, y: -2)
        buttonLabel.name = "support-link"
        buttonNode.addChild(buttonLabel)

        let adLabel = SKLabelNode(fontNamed: ".AppleSystemUIFont")
        adLabel.fontSize = 11
        adLabel.fontColor = Palette.hudText.withAlphaComponent(0.7)
        adLabel.horizontalAlignmentMode = .left
        adLabel.verticalAlignmentMode = .top
        adLabel.position = CGPoint(x: supportTitle.position.x, y: -supportCardHeight / 2 + 24)
        adLabel.text = "Or watch a short ad soon"
        supportCard.addChild(adLabel)

        let player = SKLabelNode(fontNamed: ".AppleSystemUIFont")
        player.fontSize = 13
        player.fontColor = Palette.hudText
        player.horizontalAlignmentMode = .left
        player.verticalAlignmentMode = .top
        player.position = CGPoint(
            x: -size.width / 2 + 28,
            y: -size.height / 2 + 88
        )
        cameraNode.addChild(player)
        playerLabel = player
        registerIntroNode(player)

        let rightMarginX = size.width / 2 - 24
        let onlineTitle = SKLabelNode(fontNamed: ".AppleSystemUIFont")
        onlineTitle.fontSize = 13
        onlineTitle.fontColor = Palette.hudText
        onlineTitle.horizontalAlignmentMode = .right
        onlineTitle.verticalAlignmentMode = .top
        onlineTitle.position = CGPoint(x: rightMarginX, y: size.height / 2 - 32)
        onlineTitle.text = "Online Leaderboards"
        cameraNode.addChild(onlineTitle)
        registerIntroNode(onlineTitle)

        onlineScoreLabels = (0..<onlineScoreCapacity).map { index in
            let entry = SKLabelNode(fontNamed: ".AppleSystemUIFont")
            entry.fontSize = 11.5
            entry.fontColor = Palette.hudText
            entry.horizontalAlignmentMode = .right
            entry.verticalAlignmentMode = .top
            entry.position = CGPoint(
                x: rightMarginX, y: onlineTitle.position.y - 18 - CGFloat(index) * 14)
            cameraNode.addChild(entry)
            registerIntroNode(entry)
            return entry
        }

        updatePlayerLabel()
        updateScoreboardDisplay()
    }

    private func spawnClouds(upToY targetY: CGFloat) {
        let cappedTarget = targetY + 200
        while nextCloudSpawnY < cappedTarget {
            spawnCloud(atY: nextCloudSpawnY)
            nextCloudSpawnY += CGFloat.random(in: 160...240)
        }
    }

    private func spawnCloud(atY y: CGFloat) {
        let cloud = SKNode()
        let baseAlpha: CGFloat = 0.22
        let bubbles = Int.random(in: 3...5)
        let baseWidth = CGFloat.random(in: 160...280)
        let baseHeight = baseWidth * CGFloat.random(in: 0.4...0.55)
        let bubbleOffsets: [CGPoint] = (0..<bubbles).map { index in
            let spread = baseWidth * 0.45
            let x = CGFloat.random(in: -spread...spread)
            let y = CGFloat.random(in: -baseHeight * 0.2...baseHeight * 0.2)
            return CGPoint(x: x, y: y - CGFloat(index % 2) * 6)
        }

        for offset in bubbleOffsets {
            let size = CGSize(
                width: baseWidth * CGFloat.random(in: 0.45...0.7),
                height: baseHeight * CGFloat.random(in: 0.55...0.85))
            let bubble = SKShapeNode(ellipseOf: size)
            bubble.fillColor = SKColor(white: 1.0, alpha: baseAlpha)
            bubble.strokeColor = SKColor(white: 1.0, alpha: baseAlpha * 0.7)
            bubble.position = offset
            bubble.lineWidth = 1
            cloud.addChild(bubble)
        }

        let randomX = CGFloat.random(in: -size.width / 2.2...size.width / 2.2)
        let verticalOffset = CGFloat.random(in: -60...60)
        cloud.position = CGPoint(x: randomX, y: y + verticalOffset)
        cloud.alpha = 0.0
        cloudLayer.addChild(cloud)

        let driftDistance = CGFloat.random(in: 50...100)
        let driftDuration = TimeInterval.random(in: 14...20)
        let driftDirection: CGFloat = Bool.random() ? 1 : -1
        let drift = SKAction.sequence([
            SKAction.moveBy(x: driftDistance * driftDirection, y: CGFloat.random(in: -12...12), duration: driftDuration),
            SKAction.moveBy(x: -driftDistance * driftDirection, y: CGFloat.random(in: -12...12), duration: driftDuration),
        ])
        let float = SKAction.repeatForever(drift)
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 1.6)
        cloud.run(fadeIn)
        cloud.run(float, withKey: "drift")
    }

    private func cleanupClouds() {
        let cutoff = cameraNode.position.y - size.height
        for node in cloudLayer.children {
            if node.position.y < cutoff {
                node.removeAllActions()
                node.removeFromParent()
            }
        }
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

    private func loadPersistentData() {
        let defaults = UserDefaults.standard

        if let storedName = defaults.string(forKey: PersistKeys.playerName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !storedName.isEmpty
        {
            playerName = storedName
        } else {
            playerName = "Player"
        }

        if let data = defaults.data(forKey: PersistKeys.scoreboard),
            let entries = try? JSONDecoder().decode([ScoreEntry].self, from: data)
        {
            scoreboardEntries = entries
            sortScoreboard()
            if scoreboardEntries.count > storedScoreLimit {
                scoreboardEntries = Array(scoreboardEntries.prefix(storedScoreLimit))
            }
        } else {
            scoreboardEntries = []
        }

        let storedHigh = defaults.integer(forKey: PersistKeys.highScore)
        let bestScore = scoreboardEntries.first?.score ?? 0
        highScore = max(storedHigh, bestScore)
        if highScore != storedHigh {
            defaults.set(highScore, forKey: PersistKeys.highScore)
        }
    }

    private func registerIntroNode(_ node: SKNode) {
        introHUDNodes.append(node)
        node.isHidden = !introHUDVisible
    }

    private func setIntroHUDVisible(_ visible: Bool) {
        guard introHUDVisible != visible else { return }
        introHUDVisible = visible
        introHUDNodes.forEach { $0.isHidden = !visible }
    }

    private func hideIntroHUDForRunIfNeeded() {
        if introHUDVisible {
            setIntroHUDVisible(false)
        }
    }

    private func openSupportLink() {
        guard let url = supportLink else { return }
        NSWorkspace.shared.open(url)
    }

    private func promptForPlayerNameIfNeeded() {
        let defaults = UserDefaults.standard
        let existing = defaults.string(forKey: PersistKeys.playerName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing, !existing.isEmpty {
            playerName = existing
            return
        }

        let alert = NSAlert()
        alert.messageText = "Welcome to DockJumper"
        alert.informativeText = "Enter your name for the scoreboard."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Use Default")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        inputField.placeholderString = "Player"
        alert.accessoryView = inputField

        if let window = view?.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                var name = inputField.stringValue.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if response != .alertFirstButtonReturn || name.isEmpty {
                    name = "Player"
                }
                defaults.set(name, forKey: PersistKeys.playerName)
                self?.playerName = name
                self?.view?.window?.makeFirstResponder(self)
            }
            DispatchQueue.main.async {
                window.makeFirstResponder(inputField)
            }
        } else {
            let response = alert.runModal()
            var name = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response != .alertFirstButtonReturn || name.isEmpty {
                name = "Player"
            }
            defaults.set(name, forKey: PersistKeys.playerName)
            playerName = name
            view?.window?.makeFirstResponder(self)
        }
    }

    private func recordScore(_ score: Int) {
        guard score > 0 else { return }

        scoreboardEntries.append(ScoreEntry(name: playerName, score: score, date: Date()))
        sortScoreboard()
        if scoreboardEntries.count > storedScoreLimit {
            scoreboardEntries = Array(scoreboardEntries.prefix(storedScoreLimit))
        }
        saveScoreboard()

        if let best = scoreboardEntries.first?.score, best > highScore {
            highScore = best
            UserDefaults.standard.set(highScore, forKey: PersistKeys.highScore)
        }
        updateScoreboardDisplay()
    }

    private func saveScoreboard() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(scoreboardEntries) else { return }
        UserDefaults.standard.set(data, forKey: PersistKeys.scoreboard)
    }

    private func sortScoreboard() {
        scoreboardEntries.sort {
            if $0.score == $1.score {
                return $0.date < $1.date
            }
            return $0.score > $1.score
        }
    }

    private func updateScoreboardDisplay() {
        for (index, label) in onlineScoreLabels.enumerated() {
            if index == 0 {
                label.text = "\(index + 1). Coming soon"
                label.alpha = 0.8
            } else {
                label.text = "\(index + 1). ---"
                label.alpha = 0.5
            }
        }
    }

    private func updatePlayerLabel() {
        playerLabel?.text = "Player: \(playerName)"
    }

    private func finalizeCurrentRun() {
        guard currentScore > 0 else { return }
        recordScore(currentScore)
    }

    @discardableResult
    private func addPlatform(width: CGFloat, height: CGFloat, position: CGPoint) -> SKNode {
        let platform = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 3)
        platform.fillColor = Palette.platform
        platform.strokeColor = .clear
        platform.position = position
        platform.zPosition = -1
        platform.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        platform.physicsBody?.isDynamic = false
        platform.physicsBody?.categoryBitMask = PhysicsCategory.ground
        platform.physicsBody?.friction = 1.0
        let metadata = platform.userData ?? NSMutableDictionary()
        metadata["scored"] = false
        metadata["moving"] = false
        platform.userData = metadata
        platformsCreated += 1
        if platformsCreated % 5 == 0 {
            let style = PlatformMotionStyle.style(forScore: currentScore, platformIndex: platformsCreated)
            startOscillation(for: platform, width: width, motionStyle: style)
            platform.userData?["moving"] = true
            platform.fillColor = Palette.movingPlatform
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

    private enum PlatformMotionStyle {
        case staticPlatform
        case horizontal
        case vertical
        case diagonal

        static func style(forScore score: Int, platformIndex: Int) -> PlatformMotionStyle {
            switch score {
            case ..<10:
                return .horizontal
            case 10..<15:
                return .horizontal
            case 15..<20:
                return platformIndex.isMultiple(of: 2) ? .vertical : .horizontal
            default:
                switch platformIndex % 3 {
                case 0: return .diagonal
                case 1: return .vertical
                default: return .horizontal
                }
            }
        }
    }

    private func motionParameters(for score: Int) -> (horizontalTravel: CGFloat, verticalTravel: CGFloat, speed: CGFloat) {
        var horizontal: CGFloat = 120
        var vertical: CGFloat = 0
        var speed: CGFloat = 100

        if score >= 5 {
            let boost = min(CGFloat(score - 4) * 0.08, 1.0)
            horizontal *= 1.0 + boost
            speed *= 1.0 + boost * 0.65
        }

        if score >= 12 {
            vertical = 80 * min(1.0 + CGFloat(score - 12) * 0.08, 1.8)
        }

        if score >= 18 {
            speed *= 1.15
        }

        if score >= 24 {
            horizontal *= 1.1
            speed *= 1.1
        }

        return (horizontal, vertical, speed)
    }

    private func startOscillation(for platform: SKNode, width: CGFloat, motionStyle: PlatformMotionStyle) {
        let params = motionParameters(for: currentScore)
        let halfWidth = width / 2
        let padding: CGFloat = 24
        let travel = params.horizontalTravel
        let minX = -size.width / 2 + halfWidth + padding
        let maxX = size.width / 2 - halfWidth - padding
        let proposedLeft = platform.position.x - travel
        let proposedRight = platform.position.x + travel
        let leftTarget = max(minX, proposedLeft)
        let rightTarget = min(maxX, proposedRight)

        var verticalRange: ClosedRange<CGFloat> = 0...0
        if params.verticalTravel > 0 {
            let baseY = platform.position.y
            verticalRange = (baseY - params.verticalTravel)...(baseY + params.verticalTravel)
        }

        let effectiveStyle: PlatformMotionStyle
        switch motionStyle {
        case .staticPlatform:
            effectiveStyle = .staticPlatform
        case .horizontal:
            effectiveStyle = motionStyle
        case .vertical:
            effectiveStyle = params.verticalTravel > 0 ? .vertical : .horizontal
        case .diagonal:
            effectiveStyle = params.verticalTravel > 0 ? .diagonal : .horizontal
        }

        if effectiveStyle == .horizontal && rightTarget - leftTarget < 12 {
            return
        }

        let baseSpeed = params.speed
        let duration: (CGFloat) -> TimeInterval = { distance in
            TimeInterval(max(0.7, distance / baseSpeed))
        }

        platform.removeAllActions()

        switch effectiveStyle {
        case .staticPlatform:
            platform.removeAllActions()

        case .horizontal:
            let toLeftInitial = SKAction.moveTo(
                x: leftTarget, duration: duration(abs(platform.position.x - leftTarget)))
            let toRightInitial = SKAction.moveTo(
                x: rightTarget, duration: duration(abs(rightTarget - platform.position.x)))
            let toRightFull = SKAction.moveTo(
                x: rightTarget, duration: duration(abs(rightTarget - leftTarget)))
            let toLeftFull = SKAction.moveTo(
                x: leftTarget, duration: duration(abs(rightTarget - leftTarget)))

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

        case .vertical:
            guard params.verticalTravel > 0 else { return }
            let lower = verticalRange.lowerBound
            let upper = verticalRange.upperBound
            let fullDuration = duration(abs(upper - lower))
            let toTop = SKAction.moveTo(y: upper, duration: fullDuration)
            let toBottom = SKAction.moveTo(y: lower, duration: fullDuration)
            let loop = SKAction.sequence([toTop, toBottom])
            platform.run(SKAction.repeatForever(loop), withKey: "oscillate")

        case .diagonal:
            guard params.verticalTravel > 0 else {
                startOscillation(for: platform, width: width, motionStyle: .horizontal)
                return
            }
            let lower = verticalRange.lowerBound
            let upper = verticalRange.upperBound
            let fullDuration = duration(abs(rightTarget - leftTarget))
            let toLeft = SKAction.move(to: CGPoint(x: leftTarget, y: upper), duration: fullDuration)
            let toRight = SKAction.move(to: CGPoint(x: rightTarget, y: lower), duration: fullDuration)
            let loop = SKAction.sequence([toLeft, toRight])
            platform.run(SKAction.repeatForever(loop), withKey: "oscillate")
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
        spawnClouds(upToY: targetY + 60)
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
        let groundedRecently = groundContacts > 0
            || CACurrentMediaTime() - lastGroundContactTime < 0.12
        guard groundedRecently else {
            movingPlatformUnderPlayer = nil
            return
        }
        guard let platform = movingPlatformUnderPlayer else { return }
        guard platform.parent != nil else {
            movingPlatformUnderPlayer = nil
            return
        }

        guard let body = player.physicsBody else { return }
        if abs(body.velocity.dy) > 80 {
            movingPlatformUnderPlayer = nil
            movingPlatformLastPosition = platform.position
            return
        }

        let delta = CGPoint(
            x: platform.position.x - movingPlatformLastPosition.x,
            y: platform.position.y - movingPlatformLastPosition.y
        )
        if abs(delta.x) > .ulpOfOne {
            player.position.x += delta.x
        }
        if abs(delta.y) > .ulpOfOne {
            player.position.y += delta.y
            player.physicsBody?.velocity.dy = max(player.physicsBody?.velocity.dy ?? 0, 0)
        }
        movingPlatformLastPosition = platform.position
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
            UserDefaults.standard.set(highScore, forKey: PersistKeys.highScore)
        }
        updateScoreLabel()
    }

    private func updateScoreLabel() {
        scoreLabel?.text = "Score: \(currentScore)  High: \(highScore)"
    }

    private func respawn() {
        finalizeCurrentRun()
        setIntroHUDVisible(true)
        pressingLeft = false
        pressingRight = false
        moveDirection = 0
        groundContacts = 0
        currentScore = 0
        updateScoreLabel()
        platformsCreated = 0
        movingPlatformUnderPlayer = nil
        movingPlatformLastPosition = .zero
        lastGroundContactTime = CACurrentMediaTime()

        platformNodes.forEach { $0.removeFromParent() }
        platformNodes.removeAll()
        buildStartingPlatforms()

        player.position = CGPoint(x: 0, y: -90)
        player.xScale = abs(playerBaseScale == 0 ? 1 : playerBaseScale)

        cloudLayer.removeAllChildren()
        nextCloudSpawnY = player.position.y + 140
        spawnClouds(upToY: player.position.y + size.height)
        player.yScale = 1
        player.zRotation = 0
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
