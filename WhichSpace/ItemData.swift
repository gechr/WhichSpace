import Cocoa
import EmojiKit

// MARK: - ItemData

/// Static data for symbols and emojis used by ItemPicker
enum ItemData {
    // MARK: - Symbols

    // swiftformat:disable all
    static let symbols: [String] = {
        let allSymbols: [String] = [
            // Work & Productivity
            "doc.fill", "doc.text.fill", "doc.richtext.fill", "doc.plaintext.fill", "doc.append.fill",
            "doc.badge.plus", "doc.badge.gearshape.fill", "doc.on.doc.fill", "doc.on.clipboard.fill",
            "folder.fill", "folder.badge.plus", "folder.badge.gearshape", "folder.badge.person.crop",
            "tray.fill", "tray.full.fill", "tray.2.fill", "tray.and.arrow.down.fill", "tray.and.arrow.up.fill",
            "archivebox.fill", "externaldrive.fill", "internaldrive.fill", "opticaldiscdrive.fill",
            "calendar", "calendar.badge.plus", "calendar.badge.clock", "calendar.badge.exclamationmark",
            "clock.fill", "clock.badge.checkmark.fill", "deskclock.fill", "alarm.fill", "stopwatch.fill", "timer",
            "pencil", "pencil.circle.fill", "pencil.and.outline", "highlighter", "pencil.and.scribble",
            "paperclip", "paperclip.circle.fill", "link", "link.circle.fill", "link.badge.plus",
            "bookmark.fill", "bookmark.circle.fill", "bookmark.slash.fill",
            "flag.fill", "flag.circle.fill", "flag.badge.ellipsis.fill", "flag.2.crossed.fill",
            "tag.fill", "tag.circle.fill", "tag.slash.fill",
            "pin.fill", "pin.circle.fill", "pin.slash.fill",
            "note.text", "note.text.badge.plus", "list.bullet", "list.number", "list.bullet.clipboard.fill",
            "checklist", "checklist.checked", "square.and.pencil",

            // Communication
            "envelope.fill", "envelope.open.fill", "envelope.badge.fill", "envelope.circle.fill", "mail.stack.fill",
            "message.fill", "message.circle.fill", "message.badge.fill", "ellipsis.message.fill",
            "bubble.left.fill", "bubble.right.fill", "bubble.left.and.bubble.right.fill",
            "bubble.left.and.exclamationmark.bubble.right.fill", "exclamationmark.bubble.fill",
            "quote.bubble.fill", "star.bubble.fill", "character.bubble.fill",
            "phone.fill", "phone.circle.fill", "phone.badge.plus", "phone.arrow.up.right.fill",
            "video.fill", "video.circle.fill", "video.badge.plus", "video.slash.fill",
            "bell.fill", "bell.circle.fill", "bell.badge.fill", "bell.slash.fill", "bell.and.waves.left.and.right.fill",
            "megaphone.fill", "speaker.wave.3.fill", "speaker.slash.fill",
            "mic.fill", "mic.circle.fill", "mic.slash.fill", "mic.badge.plus",

            // Media & Entertainment
            "play.fill", "play.circle.fill", "play.square.fill", "play.rectangle.fill",
            "pause.fill", "pause.circle.fill", "stop.fill", "stop.circle.fill",
            "forward.fill", "backward.fill", "forward.end.fill", "backward.end.fill",
            "shuffle", "repeat", "repeat.1", "infinity",
            "music.note", "music.note.list", "music.quarternote.3", "music.mic", "pianokeys",
            "guitars.fill", "drum.fill", "amplifier.fill",
            "headphones", "headphones.circle.fill", "hifispeaker.fill", "homepod.fill", "airpodsmax",
            "tv.fill", "tv.circle.fill", "4k.tv.fill", "play.tv.fill",
            "film.fill", "film.circle.fill", "video.fill.badge.plus", "movieclapper.fill",
            "gamecontroller.fill", "arcade.stick", "dpad.fill", "l.joystick.fill", "r.joystick.fill",
            "puzzlepiece.fill", "puzzlepiece.extension.fill",
            "theatermasks.fill", "theatermask.and.paintbrush.fill", "ticket.fill", "popcorn.fill",
            "sportscourt.fill", "soccerball", "baseball.fill", "basketball.fill", "football.fill", "tennis.racket",

            // Web & Technology
            "globe", "globe.americas.fill", "globe.europe.africa.fill", "globe.asia.australia.fill",
            "network", "network.badge.shield.half.filled",
            "wifi", "wifi.circle.fill", "wifi.exclamationmark", "wifi.slash",
            "antenna.radiowaves.left.and.right", "antenna.radiowaves.left.and.right.circle.fill",
            "server.rack", "xserve", "macpro.gen3.fill", "pc", "laptopcomputer", "desktopcomputer", "macwindow",
            "cpu.fill", "memorychip.fill", "opticaldisc.fill",
            "terminal.fill", "chevron.left.forwardslash.chevron.right", "curlybraces", "curlybraces.square.fill",
            "apple.terminal.fill", "command", "option", "control", "shift.fill", "capslock.fill",
            "power", "power.circle.fill", "powerplug.fill", "battery.100", "battery.75", "battery.50",
            "bolt.horizontal.fill", "cable.connector", "cable.connector.horizontal",
            "printer.fill", "scanner.fill", "display", "display.2", "tv.and.mediabox.fill",
            "keyboard.fill", "keyboard.badge.ellipsis.fill", "computermouse.fill", "magicmouse.fill",
            "apps.iphone", "apps.ipad", "iphone", "ipad", "applewatch", "airpods", "homepod.mini.fill",
            "qrcode", "barcode", "viewfinder", "camera.viewfinder", "doc.viewfinder.fill",
            "atom", "function", "fx", "sum", "percent", "number",

            // Creative & Design
            "paintbrush.fill", "paintbrush.pointed.fill", "pencil.tip",
            "paintpalette.fill", "eyedropper.halffull", "swatchpalette.fill",
            "photo.fill", "photo.circle.fill", "photo.stack.fill", "photo.on.rectangle.angled",
            "camera.fill", "camera.circle.fill", "camera.badge.ellipsis", "camera.macro",
            "wand.and.stars", "wand.and.rays", "wand.and.stars.inverse",
            "crop", "crop.rotate", "perspective", "skew",
            "scissors", "scissors.circle.fill", "ruler.fill", "level.fill",
            "square.on.circle.fill", "circle.grid.cross.fill", "circle.grid.2x2.fill", "circle.grid.3x3.fill", "square.stack.3d.up.fill",
            "aspectratio.fill", "arrow.up.left.and.arrow.down.right", "arrow.down.right.and.arrow.up.left",
            "lifepreserver.fill", "burn", "wand.and.rays.inverse",
            "lasso", "lasso.and.sparkles", "scribble", "scribble.variable",
            "signature", "textformat", "textformat.abc", "textformat.alt",
            "bold", "italic", "underline", "strikethrough",

            // People & Social
            "person.fill", "person.circle.fill", "person.badge.plus", "person.badge.minus",
            "person.2.fill", "person.2.circle.fill", "person.3.fill",
            "person.crop.circle.fill", "person.crop.square.fill", "person.crop.rectangle.fill",
            "person.wave.2.fill", "person.2.wave.2.fill",
            "figure.stand", "figure.walk", "figure.wave", "figure.arms.open",
            "figure.2.arms.open", "figure.2.and.child.holdinghands", "figure.and.child.holdinghands",
            "hand.raised.fill", "hand.thumbsup.fill", "hand.thumbsdown.fill", "hand.point.up.left.fill",
            "hands.clap.fill", "hands.sparkles.fill",
            "brain.head.profile", "face.smiling.fill", "face.dashed.fill",

            // Home & Buildings
            "house.fill", "house.circle.fill", "house.lodge.fill", "building.fill", "building.2.fill",
            "building.columns.fill", "building.2.crop.circle.fill",
            "bed.double.fill", "sofa.fill", "chair.lounge.fill", "chair.fill", "cabinet.fill",
            "fireplace.fill", "lamp.desk.fill", "lamp.floor.fill", "lamp.ceiling.fill", "chandelier.fill",
            "fan.fill", "fan.ceiling.fill", "air.conditioner.horizontal.fill", "dehumidifier.fill",
            "washer.fill", "dryer.fill", "dishwasher.fill", "oven.fill", "microwave.fill", "refrigerator.fill",
            "sink.fill", "bathtub.fill", "shower.fill", "toilet.fill",
            "lightswitch.on.fill", "poweroutlet.type.b.fill", "spigot.fill",
            "door.left.hand.open", "door.garage.closed", "window.vertical.open",
            "stairs", "elevator.fill", "entry.lever.keypad.fill",

            // Food & Drink
            "cup.and.saucer.fill", "mug.fill", "takeoutbag.and.cup.and.straw.fill",
            "wineglass.fill", "waterbottle.fill", "birthday.cake.fill",
            "fork.knife", "fork.knife.circle.fill", "frying.pan.fill",
            "cart.fill", "cart.circle.fill", "cart.badge.plus", "bag.fill", "bag.circle.fill", "bag.badge.plus",
            "basket.fill", "storefront.fill", "storefront.circle.fill", "shippingbox.fill",
            "carrot.fill", "leaf.fill", "tree.fill", "fish.fill",

            // Finance & Business
            "dollarsign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill", "yensign.circle.fill",
            "bitcoinsign.circle.fill", "brazilianrealsign.circle.fill",
            "creditcard.fill", "creditcard.circle.fill", "banknote.fill", "wallet.pass.fill",
            "chart.line.uptrend.xyaxis", "chart.bar.fill", "chart.pie.fill", "chart.xyaxis.line",
            "briefcase.fill", "briefcase.circle.fill", "case.fill", "latch.2.case.fill",
            "signature", "building.columns.circle.fill", "percent",

            // Health & Fitness
            "heart.text.square.fill", "heart.circle.fill", "waveform.path.ecg", "staroflife.fill",
            "cross.fill", "cross.circle.fill", "pills.fill", "pills.circle.fill",
            "bandage.fill", "syringe.fill", "facemask.fill", "medical.thermometer.fill",
            "figure.run", "figure.walk", "figure.roll", "figure.yoga", "figure.pilates", "figure.dance",
            "figure.strengthtraining.traditional", "figure.cooldown", "figure.core.training",
            "figure.cross.training", "figure.flexibility", "figure.highintensity.intervaltraining",
            "dumbbell.fill", "sportscourt.fill", "trophy.fill", "medal.fill",
            "scalemass.fill", "heart.fill",

            // Nature & Weather
            "sun.max.fill", "sun.min.fill", "sun.horizon.fill", "sunrise.fill", "sunset.fill",
            "moon.fill", "moon.circle.fill", "moon.stars.fill", "sparkles", "moon.haze.fill",
            "cloud.fill", "cloud.rain.fill", "cloud.bolt.fill", "cloud.snow.fill", "cloud.fog.fill",
            "cloud.sun.fill", "cloud.moon.fill", "cloud.drizzle.fill", "cloud.hail.fill",
            "tornado", "tropicalstorm", "hurricane", "thermometer.sun.fill", "thermometer.snowflake",
            "snowflake", "snowflake.circle.fill", "wind", "wind.circle.fill",
            "flame.fill", "flame.circle.fill", "bolt.fill", "bolt.circle.fill",
            "drop.fill", "drop.circle.fill", "humidity.fill", "umbrella.fill",
            "leaf.fill", "leaf.circle.fill", "tree.fill", "tree.circle.fill",
            "ant.fill", "ant.circle.fill", "ladybug.fill", "tortoise.fill", "hare.fill", "bird.fill",
            "fish.fill", "fish.circle.fill", "pawprint.fill", "pawprint.circle.fill",
            "fossil.shell.fill", "teddybear.fill",

            // Status & Indicators
            "checkmark.fill", "checkmark.circle.fill", "checkmark.square.fill", "checkmark.seal.fill",
            "xmark", "xmark.circle.fill", "xmark.square.fill", "xmark.seal.fill",
            "exclamationmark", "exclamationmark.circle.fill",
            "exclamationmark.triangle.fill", "exclamationmark.square.fill",
            "questionmark", "questionmark.circle.fill", "questionmark.square.fill", "questionmark.diamond.fill",
            "info.circle.fill", "info.square.fill", "info.bubble.fill",
            "plus", "plus.circle.fill", "plus.square.fill", "plus.diamond.fill",
            "minus", "minus.circle.fill", "minus.square.fill", "minus.diamond.fill",
            "multiply", "multiply.circle.fill", "divide", "divide.circle.fill",
            "equal", "equal.circle.fill", "lessthan.circle.fill", "greaterthan.circle.fill",
            "lightbulb.fill", "lightbulb.circle.fill", "lightbulb.led.fill", "lightbulb.max.fill",

            // Security & Privacy
            "lock.fill", "lock.circle.fill", "lock.square.fill", "lock.rectangle.fill",
            "lock.open.fill", "lock.slash.fill", "lock.badge.clock.fill",
            "key.fill", "key.horizontal.fill", "key.radiowaves.forward.fill",
            "key.icloud.fill", "key.viewfinder",
            "shield.fill", "shield.lefthalf.filled", "shield.slash.fill", "shield.checkered",
            "checkmark.shield.fill", "xmark.shield.fill", "exclamationmark.shield.fill",
            "eye.fill", "eye.circle.fill", "eye.slash.fill", "eye.slash.circle.fill",
            "hand.raised.slash.fill", "faceid", "touchid",
            "lock.shield.fill", "person.badge.key.fill",

            // Navigation & Maps
            "location.fill", "location.circle.fill", "location.north.fill", "location.north.circle.fill",
            "map.fill", "map.circle.fill", "mappin", "mappin.circle.fill", "mappin.and.ellipse",
            "mappin.slash.circle.fill", "pin.circle.fill",
            "safari.fill", "compass.drawing", "signpost.left.fill", "signpost.right.fill",
            "arrow.up", "arrow.down", "arrow.left", "arrow.right",
            "arrow.up.circle.fill", "arrow.down.circle.fill", "arrow.left.circle.fill", "arrow.right.circle.fill",
            "arrow.up.arrow.down", "arrow.left.arrow.right", "arrow.uturn.left", "arrow.uturn.right",
            "arrow.turn.up.left", "arrow.turn.up.right", "arrow.triangle.turn.up.right.diamond.fill",
            "chevron.up", "chevron.down", "chevron.left", "chevron.right",
            "chevron.up.circle.fill", "chevron.down.circle.fill",

            // Transportation
            "car.fill", "car.circle.fill", "car.2.fill", "suv.side.fill", "car.side.fill",
            "bolt.car.fill", "car.top.door.front.left.and.front.right.open.fill",
            "bus.fill", "bus.doubledecker.fill", "tram.fill", "tram.circle.fill",
            "cablecar.fill", "ferry.fill", "train.side.front.car", "train.side.rear.car",
            "airplane", "airplane.circle.fill", "airplane.arrival", "airplane.departure",
            "sailboat.fill", "ferry.fill", "fuelpump.fill", "ev.charger.fill",
            "bicycle", "bicycle.circle.fill", "scooter", "figure.outdoor.cycle",
            "stroller.fill", "wheelchair", "figure.roll.runningpace",

            // Objects & Tools
            "gear", "gearshape.fill", "gearshape.2.fill", "slider.horizontal.3",
            "wrench.fill", "wrench.and.screwdriver.fill", "hammer.fill", "hammer.circle.fill", "screwdriver.fill",
            "eyedropper.halffull", "paintbrush.fill", "level.fill", "ruler.fill",
            "scroll.fill", "theatermasks.fill", "crown.fill", "wand.and.stars",
            "flashlight.on.fill", "flashlight.off.fill", "lightbulb.fill",
            "binoculars.fill", "loupe", "magnifyingglass", "magnifyingglass.circle.fill",
            "clock.fill", "hourglass", "timer",
            "umbrella.fill", "umbrella.percent.fill",
            "backpack.fill", "suitcase.fill", "suitcase.rolling.fill",
            "tent.fill", "mountain.2.fill", "beach.umbrella.fill",
            "bandage.fill", "cross.vial.fill", "testtube.2",
            "wind.snow", "humidifier.fill", "heater.vertical.fill",
            "stove.fill", "cooktop.fill",

            // Education & Science
            "graduationcap.fill", "graduationcap.circle.fill",
            "book.fill", "book.circle.fill", "books.vertical.fill", "book.closed.fill",
            "text.book.closed.fill", "character.book.closed.fill", "menucard.fill",
            "newspaper.fill", "newspaper.circle.fill",
            "bookmark.fill", "bookmark.circle.fill",
            "rosette", "seal.fill",
            "globe", "globe.desk.fill",
            "atom", "scalemass.fill", "flask.fill", "testtube.2",
            "fossil.shell.fill", "laurel.leading", "laurel.trailing",
            "studentdesk", "brain", "brain.head.profile", "lightbulb.fill",

            // Arrows & Symbols
            "arrow.up.circle.fill", "arrow.down.circle.fill", "arrow.left.circle.fill", "arrow.right.circle.fill",
            "arrow.up.square.fill", "arrow.down.square.fill",
            "arrow.clockwise", "arrow.counterclockwise", "arrow.2.squarepath", "arrow.triangle.2.circlepath",
            "arrow.3.trianglepath", "arrowtriangle.up.fill", "arrowtriangle.down.fill",
            "chevron.up.circle.fill", "chevron.down.circle.fill", "chevron.compact.up", "chevron.compact.down",

            // Shapes & Stars
            "circle.fill", "circle.lefthalf.filled", "circle.righthalf.filled", "circle.tophalf.filled",
            "circle.bottomhalf.filled", "circle.inset.filled", "circle.dashed",
            "oval.fill", "oval.portrait.fill", "capsule.fill", "capsule.portrait.fill",
            "square.fill", "square.lefthalf.filled", "square.righthalf.filled", "square.tophalf.filled",
            "square.bottomhalf.filled", "square.inset.filled", "square.dashed",
            "app.fill", "rectangle.fill", "rectangle.portrait.fill",
            "triangle.fill", "triangle.lefthalf.filled", "triangle.righthalf.filled",
            "diamond.fill", "diamond.lefthalf.filled", "diamond.righthalf.filled",
            "octagon.fill", "hexagon.fill", "pentagon.fill",
            "seal.fill", "shield.fill", "rhombus.fill",
            "star.fill", "star.circle.fill", "star.square.fill", "star.leadinghalf.filled",
            "heart.fill", "heart.circle.fill", "heart.square.fill",
            "suit.heart.fill", "suit.club.fill", "suit.spade.fill", "suit.diamond.fill",
            "bolt.fill", "bolt.circle.fill", "bolt.square.fill",
            "sparkle", "sparkles", "rays", "slowmo", "timelapse",
            "burst.fill", "waveform", "waveform.circle.fill",
        ]
        // swiftformat:enable all

        // Filter to only symbols that exist on this system, then shuffle with fixed seed
        var rng = SeededRandomNumberGenerator(seed: 42)
        let available = allSymbols.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
        return available.shuffled(using: &rng)
    }()

    // MARK: - Emojis

    /// Check if an emoji string contains a skin tone modifier
    private static func hasSkinToneModifier(_ emoji: String) -> Bool {
        emoji.unicodeScalars.contains { SkinTone.modifierScalars.contains($0) }
    }

    /// All emojis from EmojiKit, excluding pre-applied skin tone variants
    static let emojis: [String] = Emoji.all
        .map(\.char)
        .filter { !hasSkinToneModifier($0) }
}

// MARK: - Seeded Random Number Generator

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // xorshift64 algorithm
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
