import IslandCore
import SpriteKit
import SwiftUI

struct GameView: View {
    @StateObject private var game = Game()
    @State private var hovered: Recipe?

    private var engine: GameEngine { game.engine }
    private var state: GameState { game.engine.state }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                SpriteView(scene: game.scene)
                    .frame(width: CGFloat(IslandMap.viewWidth) * px, height: CGFloat(IslandMap.viewHeight) * px)
                    .overlay { overlay }
                side
            }
            .frame(height: CGFloat(IslandMap.viewHeight) * px)
            HStack(spacing: 0) {
                log
                whereabouts
            }
            .frame(height: 76 * px)
        }
        .frame(width: 480 * px)
        .background(Color(hex: Ink.wood))
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 5 * px) {
            PixelText("Day \(state.day)/\(engine.balance.stormDay - 1)")
            PixelImage(image: state.weather == .rain ? Art.rain : game.isNight ? Art.moon : Art.sun)
            PixelText(game.clockText)
            PixelBar(value: Double(state.hoursLeft) / Double(engine.balance.hoursPerDay), color: 0xf9d65c, width: 30)
                .help("Daylight left")
            Spacer()
            need(Art.drop, state.needs.thirst, 0x4a9bdc, "Thirst")
            need(Art.fruit, state.needs.hunger, 0xf08a3c, "Hunger")
            need(Art.moon, 100 - state.needs.fatigue, 0x9a7ad0, "Energy")
            need(Art.heart, state.needs.health, 0xe0564c, "Health")
            Button { game.paused.toggle() } label: {
                PixelText(game.paused ? ">" : "II")
                    .frame(width: 16 * px, height: 14 * px)
                    .pixelPanel(face: Ink.panelDark)
            }
            .buttonStyle(.plain)
            .help("Pause (P)")
        }
        .padding(.horizontal, 6 * px)
        .frame(height: 20 * px)
        .frame(maxWidth: .infinity)
        .pixelPanel()
    }

    private func need(_ icon: CGImage, _ value: Double, _ color: UInt32, _ name: String) -> some View {
        HStack(spacing: 2 * px) {
            PixelImage(image: icon)
            PixelBar(value: value / 100, color: color, width: 36)
        }
        .help("\(name) \(Int(value))")
    }

    // MARK: Side panel

    private var side: some View {
        VStack(alignment: .leading, spacing: px) {
            heading("Skills")
            ForEach(Skill.allCases, id: \.self) { skill in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        PixelText(skill.displayName)
                        Spacer()
                        PixelText("Lv \(engine.level(skill))", color: Ink.faint)
                    }
                    PixelBar(value: state.skills.progress(skill, balance: engine.balance), color: 0x8fcf5a, width: 116, height: 4)
                }
            }

            heading("Bag")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], alignment: .leading, spacing: px) {
                ForEach(Item.allCases, id: \.self) { item in
                    HStack(spacing: 2 * px) {
                        PixelImage(image: Art.icon(item))
                        PixelText("\(state.count(item))", color: state.count(item) > 0 ? Ink.text : Ink.faint)
                        Spacer(minLength: 0)
                    }
                    .help(item.displayName)
                }
            }

            heading("Rescue")
            let steps = engine.rescueChecklist
            let names = ["Find the summit", "Signal frame", "Dry wood \(state.count(.dryWood))/\(engine.balance.signalDryWood)",
                         "Survival Lv \(engine.balance.signalMinSurvival)"]
            ForEach(Array(zip(names, steps)), id: \.0) { name, step in
                HStack(spacing: 2 * px) {
                    PixelImage(image: step.done ? Art.check : Art.todo)
                    PixelText(name, color: step.done ? Ink.text : Ink.faint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(6 * px)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelPanel()
    }

    private func heading(_ title: String) -> some View {
        PixelText(title.uppercased(), color: 0xb5651d)
            .padding(.top, px)
    }

    // MARK: Log

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: px) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        PixelText(line, color: index >= lines.count - 2 ? Ink.text : Ink.faint, wrap: 164)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6 * px)
            }
            .onChange(of: lines.count) { count in
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
        .frame(width: 180 * px)
        .pixelPanel(face: 0xfff3d6)
    }

    private var lines: [String] {
        game.journal.notes.suffix(2) + state.log
    }

    // MARK: Where you are

    private var whereabouts: some View {
        VStack(alignment: .leading, spacing: 3 * px) {
            HStack(spacing: 3 * px) {
                PixelText(game.here.displayName.uppercased(), color: 0xb5651d)
                ForEach(Item.allCases.filter { game.here.yields.base(for: $0) > 0 }, id: \.self) { item in
                    PixelImage(image: Art.icon(item)).help(item.displayName)
                }
            }
            PixelText(status, wrap: 280)
            Spacer(minLength: 0)
            PixelText("Arrows/WASD walk   Space use", color: Ink.faint)
            PixelText("C craft   M map   P pause", color: Ink.faint)
        }
        .padding(6 * px)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelPanel()
    }

    private var status: String {
        if game.mapOpen { return "The whole island. Press M to go back." }
        if game.sleeping { return "Sleeping..." }
        if let working = game.working { return working.doing }
        if let prompt = game.prompt { return prompt.text }
        return "Walk up to trees, bushes, rocks, water or fog."
    }

    // MARK: Crafting

    private var craftMenu: some View {
        VStack(alignment: .leading, spacing: 2 * px) {
            PixelText(hovered.map(needs) ?? "CRAFT", color: 0xb5651d)
            ForEach(Array(game.recipes.enumerated()), id: \.element) { index, recipe in
                let enabled = game.canCraft(recipe)
                Button { game.craft(recipe) } label: {
                    HStack(spacing: 3 * px) {
                        PixelText("\(index + 1)", color: Ink.faint)
                        PixelImage(image: Action.craft(recipe).icon)
                        PixelText(recipe.displayName, color: enabled ? Ink.text : Ink.faint)
                        Spacer(minLength: 0)
                        PixelText("\(engine.hours(for: .craft(recipe)))h", color: Ink.faint)
                    }
                    .padding(.horizontal, 4 * px)
                    .frame(width: 150 * px, height: 15 * px)
                    .pixelPanel(face: enabled ? (hovered == recipe ? 0xfffaf0 : 0xfff3d6) : Ink.panelDark)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? recipe : (hovered == recipe ? nil : hovered) }
            }
            PixelText("1-\(game.recipes.count) build   C close", color: Ink.faint)
        }
        .padding(7 * px)
        .pixelPanel()
    }

    /// What a recipe takes, including what is still missing.
    private func needs(_ recipe: Recipe) -> String {
        let spec = recipe.spec
        var parts = spec.cost.map { "\($0.1) \($0.0.displayName.lowercased())" }
        if engine.level(.crafting) < spec.requiredLevel { parts.append("Crafting Lv \(spec.requiredLevel)") }
        if let needed = spec.requiresStructure, !state.has(needed) { parts.append(needed.displayName.lowercased()) }
        if let region = spec.requiresRegion, region != game.here { parts.append("at the \(region.displayName.lowercased())") }
        return parts.joined(separator: ", ")
    }

    // MARK: Over the island

    @ViewBuilder
    private var overlay: some View {
        if let outcome = state.outcome {
            VStack(spacing: 5 * px) {
                PixelText(title(for: outcome), scale: 2)
                PixelText(game.saveError ?? "\(game.journal.runs) castaways so far, \(game.journal.rescues) rescued", color: Ink.faint)
                Button(action: game.restart) {
                    PixelText("Space: New castaway")
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
            PixelText("PAUSED", scale: 2)
                .padding(8 * px)
                .pixelPanel()
        }
    }

    private func title(for outcome: Outcome) -> String {
        switch outcome {
        case let .rescued(day): "Rescued on day \(day)!"
        case let .died(_, cause): "Lost to \(cause.rawValue)"
        case .storm: "Lost to the storm"
        }
    }
}
