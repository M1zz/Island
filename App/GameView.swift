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
            // No health bar: when the body is failing, the edges of the world go red.
            .overlay {
                Rectangle()
                    .strokeBorder(Color(hex: 0xb01818), lineWidth: 5 * px)
                    .opacity(min(0.85, max(0, (60 - state.needs.health) / 60)))
                    .allowsHitTesting(false)
            }
            // The map gets the whole window to itself.
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 3 * px) {
                    needs
                    skills
                }
                .padding(4 * px)
                .opacity(game.mapOpen ? 0 : 1)
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 3 * px) {
                    calendar
                    rescue
                }
                .padding(4 * px)
                .opacity(game.mapOpen ? 0 : 1)
            }
            .overlay(alignment: .bottomLeading) { whereabouts.padding(4 * px) }
            .overlay(alignment: .bottom) { bag.padding(4 * px).opacity(game.mapOpen ? 0 : 1) }
            .overlay(alignment: .bottomTrailing) { controls.padding(4 * px) }
            .overlay { centre }
    }

    // MARK: Body and mind

    private var needs: some View {
        HStack(spacing: 5 * px) {
            // What actually kills a castaway: thirst, hunger, cold, exhaustion.
            gauge(Art.drop, state.needs.thirst, 0x4a9bdc)
            gauge(Art.stomach, state.needs.hunger, 0xf08a3c)
            HStack(spacing: 2 * px) {
                PixelImage(image: Art.thermometer)
                PixelDial(value: state.needs.temperature / 100, width: 30)
            }
            gauge(Art.bolt, 100 - state.needs.fatigue, 0x7fc653)
        }
        .padding(4 * px)
        .pixelPanel()
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
            PixelImage(image: state.weather == .rain ? Art.rain : game.isNight ? Art.moon : Art.sun)
            PixelBar(value: Double(state.hoursLeft) / Double(engine.balance.hoursPerDay), color: 0xf9d65c, width: 30)
            // One pip a day, counting down to the storm.
            HStack(spacing: px) {
                ForEach(1..<engine.balance.stormDay, id: \.self) { day in
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

    // MARK: The way home

    private var rescue: some View {
        let done = engine.rescueChecklist.map(\.done)
        return VStack(alignment: .leading, spacing: 2 * px) {
            HStack(spacing: 3 * px) {
                PixelImage(image: Art.ship)
                Spacer(minLength: 0)
            }
            step(done[0]) { PixelImage(image: Art.peak) }
            step(done[1]) { PixelImage(image: Art.signalFrame) }
            step(done[2]) {
                PixelImage(image: Art.dryLog)
                PixelBar(value: Double(state.count(.dryWood)) / Double(engine.balance.signalDryWood), color: 0xedc96c, width: 20, height: 4)
            }
            step(done[3]) {
                PixelImage(image: Art.flame)
                PixelImage(image: Art.up)
                PixelImage(image: Art.number(engine.balance.signalMinSurvival))
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
                    PixelImage(image: Art.ship).padding(.leading, 6 * px)
                    PixelImage(image: Art.number(game.journal.rescues))
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
        case let .rescued(on): (picture, day, cause) = (Art.ship, on, nil)
        case .storm: (picture, day, cause) = (Art.storm, state.day, nil)
        case let .died(on, why):
            (picture, day) = (Art.skull, on)
            cause = why == .dehydration ? Art.drop : why == .starvation ? Art.stomach : why == .exposure ? Art.thermometer : why == .heatstroke ? Art.sun : Art.heart
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
