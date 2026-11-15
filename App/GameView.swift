import IslandCore
import SpriteKit
import SwiftUI

/// The island fills the window; everything you need to know floats over it as pictures and gauges.
struct GameView: View {
    @StateObject private var game = Game()
    @ObservedObject private var sound = Sound.shared

    private var engine: GameEngine { game.engine }
    private var state: GameState { game.engine.state }

    var body: some View {
        SpriteView(scene: game.scene)
            .frame(width: CGFloat(IslandMap.viewWidth) * px, height: CGFloat(IslandMap.viewHeight) * px)
            // Nothing but the picture while the opening plays.
            .overlay { hud.opacity(game.intro ? 0 : 1).animation(.easeIn(duration: 0.5), value: game.intro) }
    }

    /// The screen is the island. Panels come up only when they have something to say,
    /// or all at once while Tab is held open.
    private enum Panel { case bag, day, keys }
    @State private var glimpses: [Panel: Date] = [:]

    private func glimpse(_ panel: Panel, seconds: Double = 3.5) {
        let until = Date().addingTimeInterval(seconds)
        glimpses[panel] = until
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if glimpses[panel] == until { glimpses[panel] = nil }
        }
    }

    private func shows(_ panel: Panel) -> Bool { game.showAll || glimpses[panel] != nil }

    private var hud: some View {
        let all = game.showAll && !game.mapOpen
        return Color.clear
            // No health bar: when the body is failing, the edges of the world go red.
            .overlay {
                Rectangle()
                    .strokeBorder(Color(hex: 0xb01818), lineWidth: 5 * px)
                    .opacity(min(0.85, max(0, (60 - state.needs.health) / 60)))
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 3 * px) {
                    needs
                    skills.shown(all)
                }
                .padding(4 * px)
                .shown(!game.mapOpen)
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 3 * px) {
                    calendar.shown(shows(.day))
                    rescue.shown(all || (glimpses[.day] != nil && !game.mapOpen))
                }
                .padding(4 * px)
                .shown(!game.mapOpen)
            }
            .overlay(alignment: .bottomLeading) { whereabouts.padding(4 * px).shown(game.showAll || game.mapOpen) }
            .overlay(alignment: .bottom) { bag.padding(4 * px).shown(shows(.bag) && !game.mapOpen) }
            .overlay(alignment: .bottomTrailing) { controls.padding(4 * px).shown(shows(.keys)) }
            .overlay { centre }
            .animation(.easeInOut(duration: 0.25), value: game.showAll)
            .animation(.easeInOut(duration: 0.25), value: glimpses)
            .onChange(of: Item.allCases.map(state.count)) { _ in glimpse(.bag) }
            .onChange(of: state.day) { _ in glimpse(.day, seconds: 5) }
            .onChange(of: game.intro) { _ in glimpse(.keys, seconds: 8) }
    }

    // MARK: Body and mind

    /// Only what is going wrong: thirst, hunger, heat or cold, exhaustion.
    private var needs: some View {
        let needs = state.needs, all = game.showAll
        let dry = needs.oxygen < 35, empty = needs.hunger < 35, spent = needs.fatigue > 65
        let fevered = needs.temperature < 30 || needs.temperature > 70
        return HStack(spacing: 5 * px) {
            if all || dry { gauge(Art.drop, needs.oxygen, 0x4a9bdc) }
            if all || empty { gauge(Art.stomach, needs.hunger, 0xf08a3c) }
            if all || fevered {
                HStack(spacing: 2 * px) {
                    PixelImage(image: Art.thermometer)
                    PixelDial(value: needs.temperature / 100, width: 30)
                }
            }
            if all || spent { gauge(Art.bolt, 100 - needs.fatigue, 0x7fc653) }
        }
        .padding(4 * px)
        .pixelPanel()
        .shown(all || dry || empty || fevered || spent)
    }

    /// Runs red when it is nearly empty.
    private func gauge(_ icon: CGImage, _ value: Double, _ color: UInt32) -> some View {
        HStack(spacing: 2 * px) {
            PixelImage(image: icon)
            PixelBar(value: value / 100, color: value < 25 ? 0xd0342c : color, width: 30)
        }
    }

    private var skills: some View {
        VStack(alignment: .leading, spacing: 2 * px) {
            ForEach(Skill.allCases, id: \.self) { skill in
                HStack(spacing: 2 * px) {
                    PixelImage(image: Art.icon(skill))
                    PixelImage(image: Art.number(engine.level(skill)))
                    PixelBar(value: state.skills.progress(skill, balance: engine.balance), color: 0x8fcf5a, width: 24, height: 4)
                }
            }
            // The tools that open the island, ghosted until made.
            HStack(spacing: 3 * px) {
                ForEach(Structure.allCases.filter(\.isTool), id: \.self) { tool in
                    PixelImage(image: Art.picture(tool)).opacity(state.has(tool) ? 1 : 0.35)
                }
            }
            .padding(.top, px)
        }
        .padding(4 * px)
        .pixelPanel()
    }

    // MARK: Time

    private var calendar: some View {
        HStack(spacing: 4 * px) {
            PixelImage(image: state.weather == .storm ? Art.rain : game.isNight ? Art.moon : Art.sun)
            PixelBar(value: Double(state.hoursLeft) / Double(engine.balance.hoursPerDay), color: 0xf9d65c, width: 30)
            // One pip a day, counting down to the storm.
            HStack(spacing: px) {
                ForEach(1..<engine.balance.winterDay, id: \.self) { day in
                    Rectangle()
                        .fill(Color(hex: day < state.day ? Ink.border : day == state.day ? 0xf08a3c : Ink.panelDark))
                        .frame(width: 2 * px, height: (day == state.day ? 7 : 5) * px)
                }
            }
            PixelImage(image: Art.storm)
            Button { sound.muted.toggle() } label: {
                PixelImage(image: sound.muted ? Art.speakerOff : Art.speaker)
                    .frame(width: 13 * px, height: 12 * px)
                    .pixelPanel(face: Ink.panelDark)
            }
            .buttonStyle(.plain)
            Button { game.paused.toggle() } label: {
                PixelImage(image: game.paused ? Art.play : Art.pause)
                    .frame(width: 13 * px, height: 12 * px)
                    .pixelPanel(face: Ink.panelDark)
            }
            .buttonStyle(.plain)
        }
        .padding(4 * px)
        .pixelPanel()
    }

    // MARK: The planet

    /// How far it has turned, and which of the three machines stand.
    private var rescue: some View {
        VStack(alignment: .leading, spacing: 2 * px) {
            HStack(spacing: 3 * px) {
                PixelImage(image: Art.planet)
                PixelBar(value: state.terraform / 100, color: 0x7fc653, width: 30)
            }
            ForEach(engine.terraformChecklist, id: \.structure) { machine in
                step(machine.done) { PixelImage(image: Art.picture(machine.structure)) }
            }
        }
        .padding(4 * px)
        .fixedSize()
        .pixelPanel()
    }

    private func step(_ done: Bool, @ViewBuilder _ what: () -> some View) -> some View {
        HStack(spacing: 3 * px) {
            PixelImage(image: done ? Art.check : Art.todo)
            what()
        }
    }

    // MARK: Bottom row

    private var whereabouts: some View {
        HStack(spacing: 3 * px) {
            PixelText(game.cell)
            PixelImage(image: Art.icon(game.here))
            ForEach(Item.allCases.filter { game.here.yields.base(for: $0) > 0 }, id: \.self) { item in
                PixelImage(image: Art.icon(item))
            }
        }
        .padding(4 * px)
        .pixelPanel()
    }

    private var bag: some View {
        HStack(spacing: 2 * px) {
            ForEach(Item.allCases, id: \.self) { item in
                let count = state.count(item)
                VStack(spacing: px) {
                    PixelImage(image: Art.icon(item)).opacity(count > 0 ? 1 : 0.5)
                    PixelImage(image: Art.number(count, color: count > 0 ? Ink.text : Ink.faint))
                }
                .frame(width: 22 * px, height: 31 * px)
                .pixelPanel(face: 0xfff3d6)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 3 * px) {
            PixelImage(image: Art.arrows)
            PixelImage(image: Art.spaceKey)
            PixelImage(image: Art.key("TAB"))
            keyButton("C", Art.hammer, lit: game.crafting, action: game.toggleCrafting)
            keyButton("M", Art.mapIcon, lit: game.mapOpen, action: game.toggleMap)
                .opacity(state.has(.map) ? 1 : 0.45)
        }
        .padding(4 * px)
        .pixelPanel()
    }

    private func keyButton(_ legend: String, _ icon: CGImage, lit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2 * px) {
                PixelImage(image: Art.key(legend))
                PixelImage(image: icon)
            }
            .padding(2 * px)
            .pixelPanel(face: lit ? 0xf9d65c : Ink.panelDark)
        }
        .buttonStyle(.plain)
    }

    // MARK: Crafting

    private var craftMenu: some View {
        VStack(alignment: .leading, spacing: 2 * px) {
            ForEach(Array(game.recipes.enumerated()), id: \.element) { index, recipe in
                let spec = recipe.spec
                let enabled = game.canCraft(recipe)
                Button { game.craft(recipe) } label: {
                    HStack(spacing: 3 * px) {
                        PixelImage(image: Art.key("\(index + 1)"))
                        output(spec).frame(width: 24 * px)
                        ForEach(spec.cost, id: \.0) { item, amount in
                            PixelImage(image: Art.icon(item))
                            PixelImage(image: Art.number(amount, color: state.count(item) >= amount ? Ink.text : 0xd0342c))
                        }
                        Spacer(minLength: 6 * px)
                        // Only what is still missing.
                        if engine.level(.crafting) < spec.requiredLevel {
                            PixelImage(image: Art.hammer)
                            PixelImage(image: Art.up)
                            PixelImage(image: Art.number(spec.requiredLevel, color: 0xd0342c))
                        }
                        if let needed = spec.requiresStructure, !state.has(needed) {
                            PixelImage(image: Art.picture(needed))
                            PixelImage(image: Art.cross)
                        }
                        if let region = spec.requiresRegion, region != game.here {
                            PixelImage(image: Art.compass)
                            PixelImage(image: Art.icon(region))
                        }
                        PixelImage(image: Art.hourglass)
                        PixelImage(image: Art.number(engine.hours(for: .craft(recipe))))
                    }
                    .padding(.horizontal, 4 * px)
                    .frame(width: 230 * px, height: 20 * px)
                    .pixelPanel(face: enabled ? 0xfff3d6 : Ink.panelDark)
                    .opacity(enabled ? 1 : 0.8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6 * px)
        .pixelPanel()
    }

    @ViewBuilder
    private func output(_ spec: Recipe.Spec) -> some View {
        switch spec.output {
        case let .structure(structure):
            PixelImage(image: Art.picture(structure))
        case let .items(item, amount):
            HStack(spacing: 2 * px) {
                PixelImage(image: Art.icon(item))
                PixelImage(image: Art.number(amount))
            }
        }
    }

    // MARK: Middle of the screen

    @ViewBuilder
    private var centre: some View {
        if let outcome = state.outcome {
            VStack(spacing: 6 * px) {
                ending(outcome)
                HStack(spacing: 3 * px) {
                    PixelImage(image: Art.heroIdle)
                    PixelImage(image: Art.number(game.journal.runs))
                    PixelImage(image: Art.planet).padding(.leading, 6 * px)
                    PixelImage(image: Art.number(game.journal.successes))
                }
                if let error = game.saveError { PixelText(error, color: 0xd0342c, wrap: 200) }
                Button(action: game.restart) {
                    HStack(spacing: 3 * px) {
                        PixelImage(image: Art.spaceKey)
                        PixelImage(image: Art.play)
                    }
                    .padding(.horizontal, 8 * px)
                    .frame(height: 17 * px)
                    .pixelPanel(face: 0xf9d65c)
                }
                .buttonStyle(.plain)
            }
            .padding(10 * px)
            .pixelPanel()
        } else if game.crafting {
            craftMenu
        } else if game.paused {
            PixelImage(image: Art.pause, scale: 3)
                .padding(10 * px)
                .pixelPanel()
        }
    }

    /// How it ended, and on which day.
    private func ending(_ outcome: Outcome) -> some View {
        let picture: CGImage, day: Int, cause: CGImage?
        switch outcome {
        case let .habitable(on): (picture, day, cause) = (Art.planet, on, nil)
        case .winter: (picture, day, cause) = (Art.storm, state.day, nil)
        case let .died(on, why):
            (picture, day) = (Art.skull, on)
            cause = why == .suffocation ? Art.drop : why == .starvation ? Art.stomach : why == .exposure ? Art.thermometer : why == .heatstroke ? Art.sun : Art.heart
        }
        return VStack(spacing: 5 * px) {
            HStack(spacing: 4 * px) {
                PixelImage(image: picture, scale: 3)
                if let cause {
                    PixelImage(image: cause, scale: 2)
                    PixelImage(image: Art.cross, scale: 2)
                }
            }
            HStack(spacing: 3 * px) {
                PixelImage(image: Art.sun)
                PixelImage(image: Art.number(day))
            }
        }
    }
}

private extension View {
    /// There or not, without leaving a dead spot that swallows clicks.
    func shown(_ on: Bool) -> some View {
        opacity(on ? 1 : 0).allowsHitTesting(on)
    }
}
