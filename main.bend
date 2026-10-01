import Base
import ./voxel.bend as V
import ./render.bend as R
import ./dump.bend as D

type Mode is Data:
	Interactive{}
	Dump{path: String}
	Benchmark{frames: Nat}

type Options is Data:
	Options{mode: Mode, cut: Bool, tile_depth: Nat, fork_depth: Nat}

type Model is Type:
	Model{body: V.Body, surface: V.Surface, scene: R.RenderScene, tile_depth: Nat, fork_depth: Nat}

def Model.finish(+tile_depth: Nat, fork_depth: Nat, result: V.Body & V.Surface) -> Model:
	(body, +surface) = result
	Model{body, surface, R.RenderScene.build(surface, tile_depth), tile_depth, fork_depth}

def Model.init(+tile_depth: Nat, fork_depth: Nat) -> Model:
	Model.finish(tile_depth, fork_depth, V.Surface.build(V.Body.solid(3n)))

def Model.destroy(model: Model, cell: V.Cell) -> Model:
	Model{body, surface, scene, +tile_depth, fork_depth} = model
	Model.finish(tile_depth, fork_depth, V.Surface.build(V.Body.destroy(body, V.Sphere{cell, 3})))

def Model.reset(model: Model) -> Model:
	Model{body, surface, scene, tile_depth, fork_depth} = model
	Model.init(tile_depth, fork_depth)

def Model.drawn(body: V.Body, surface: V.Surface, tile_depth: Nat, fork_depth: Nat, rendered: Image & R.RenderScene) -> Model & Image:
	(image, scene) = rendered
	(Model{body, surface, scene, tile_depth, fork_depth}, image)

def Model.view(model: Model) -> Model & Image:
	Model{body, surface, scene, tile_depth, +fork_depth} = model
	Model.drawn(body, surface, tile_depth, fork_depth, R.RenderScene.image(scene, fork_depth))

def Model.clicked(hit: Maybe<&2, V.Cell>, model: Model) -> Model:
	match hit:
		case None{}:
			model
		case Some{cell}:
			Model.destroy(model, cell)

def Model.click(model: Model, x: U32, y: U32) -> Model:
	Model{body, surface, +scene, tile_depth, fork_depth} = model
	Model.clicked(R.RenderScene.pick(scene, x, y), Model{body, surface, scene, tile_depth, fork_depth})

def Model.event(event: Event, model: Model) -> Maybe<Model>:
	match event:
		case Close{}:
			None{}
		case Key{27, True{}}:
			None{}
		case Key{32, True{}}:
			Some{Model.destroy(model, V.Cell{6, 6, 6})}
		case Key{114, True{}}:
			Some{Model.reset(model)}
		case Key{82, True{}}:
			Some{Model.reset(model)}
		case Mouse{x, y, 0, True{}}:
			Some{Model.click(model, x, y)}
		case _:
			Some{model}

def Model.events(events: List<Event>, model: Model) -> Maybe<Model>:
	match events:
		case Nil{}:
			Some{model}
		case Con{event, rest}:
			Maybe.bind(&1, Model, Model, Model.event(event, model), m => Model.events(rest, m))

def Model.next(next: Maybe<Model>) -> IO(Maybe<Model>):
	match next:
		case None{}:
			IO.pure(Maybe<Model>, None{})
		case Some{model}:
			do IO<Maybe<Model>>:
				barrier : Nat <- IO.now()
				return Some{model}

def Model.tick(events: List<Event>, model: Model) -> IO(Maybe<Model>):
	Model.next(Model.events(events, model))

def Options.args(args: List<String>) -> List<&2, String>:
	match args:
		case Nil{}:
			Nil{}
		case Con{arg, rest}:
			arg <> Options.args(rest)

def Options.flag(args: List<&2, String>, +flag: String, found: Bool) -> Maybe<&2, String>:
	match args:
		case Nil{}:
			None{}
		case Con{+arg, rest}:
			match found:
				case True{}:
					Some{arg}
				case False{}:
					Options.flag(rest, flag, String.eq(arg, flag))

def Options.has(args: List<&2, String>, +flag: String) -> Bool:
	match args:
		case Nil{}:
			False{}
		case Con{arg, rest}:
			Bool.or(String.eq(arg, flag), Options.has(rest, flag))

def Options.number(value: Maybe<&2, String>, fallback: U32) -> U32:
	match value:
		case None{}:
			fallback
		case Some{text}:
			Maybe.default(&2, U32, U32.read(text), fallback)

def Options.mode(dump: Maybe<&2, String>, bench: Maybe<&2, String>) -> Mode:
	match dump:
		case Some{path}:
			Dump{path}
		case None{}:
			match bench:
				case Some{n}:
					Benchmark{U32.to_nat(Maybe.default(&2, U32, U32.read(n), 60))}
				case None{}:
					Interactive{}

def Options.clamp(valid: Bool, n: U32, fallback: U32) -> U32:
	match valid:
		case True{}:
			n
		case False{}:
			fallback

def Options.depth(value: Maybe<&2, String>, +fallback: U32) -> Nat:
	+n = Options.number(value, fallback)
	U32.to_nat(Options.clamp((n <= 9 : U32), n, fallback))

def Options.parse(+args: List<&2, String>) -> Options:
	Options{Options.mode(Options.flag(args, "--dump", False{}), Options.flag(args, "--bench", False{})), Options.has(args, "--cut"),
		Options.depth(Options.flag(args, "--tile-depth", False{}), 5), Options.depth(Options.flag(args, "--fork-depth", False{}), 5)}

def Model.initial(cut: Bool, tile_depth: Nat, fork_depth: Nat) -> Model:
	match cut:
		case False{}:
			Model.init(tile_depth, fork_depth)
		case True{}:
			Model.destroy(Model.init(tile_depth, fork_depth), V.Cell{6, 6, 6})

def Run.dump(path: String, drawn: Model & Image) -> IO(Unit):
	(model, image) = drawn
	D.Dump.ppm(path, image)

def Bench.edit(frame: U32, model: Model) -> Model:
	match frame:
		case 8:
			Model.destroy(model, V.Cell{6, 6, 6})
		case 16:
			Model.reset(model)
		case _:
			model

def Bench.shown(shown: Window & Image & List<Event>) -> IO(Window):
	(window, image, events) = shown
	do IO<Window>:
		Unit <- IO.pure(Unit, Image.drop!(image))
		return window

def Bench.frame(window: Window, drawn: Model & Image) -> IO(Window & Model):
	(model, image) = drawn
	do IO<Window & Model>:
		shown : Window & Image & List<Event> <- Window.frame(window, image)
		window : Window <- Bench.shown(shown)
		return (window, model)

def Bench.loop(fuel: Nat, +frame: U32, state: Window & Model) -> IO(Window & Model):
	match fuel:
		case 0n:
			IO.pure(Window & Model, state)
		case 1n+rest:
			(window, model) = state
			do IO<Window & Model>:
				model : Model = Bench.edit((frame % 24 : U32), model)
				barrier : Nat <- IO.now()
				result : Window & Model <- Bench.frame(window, Model.view(model))
				Bench.loop(rest, (frame + 1 : U32), result)

def Bench.close(state: Window & Model) -> IO(Unit):
	(window, model) = state
	Window.close(window)

def Bench.run(+frames: Nat, model: Model) -> IO(Unit):
	do IO<Unit>:
		window : Window <- IO.try(Window, Window.open("Bend Voxel Rewrite | benchmark", 512, 512))
		warm : Window & Model <- Bench.loop(8n, 0, (window, model))
		start : Nat <- IO.now()
		finished : Window & Model <- Bench.loop(frames, 8, warm)
		finish : Nat <- IO.now()
		Bench.close(finished)
		IO.print("frames=" ++ Nat.show(frames) ++ " elapsed_ms=" ++ Nat.show(Nat.sub(finish, start)))

def Run.mode(mode: Mode, model: Model) -> IO(Unit):
	match mode:
		case Dump{path}:
			do IO<Unit>:
				barrier : Nat <- IO.now()
				Run.dump(path, Model.view(model))
		case Benchmark{frames}:
			Bench.run(frames, model)
		case Interactive{}:
			App.run(~Model, ~App{Model.view, Model.tick}, "Bend Voxel Rewrite | Space destroy | click carve | R reset | Esc exit", 512, 512, model)

def Run.options(options: Options) -> IO(Unit):
	Options{mode, cut, tile_depth, fork_depth} = options
	Run.mode(mode, Model.initial(cut, tile_depth, fork_depth))

def main() -> IO(Unit):
	do IO<Unit>:
		args : List<String> <- IO.args()
		Run.options(Options.parse(Options.args(args)))
