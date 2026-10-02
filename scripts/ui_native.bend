import Base

def Desktop.key(display: String, id: U32, code: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
	import "./ui_native.c"
	import "./ui_native.js"

def Desktop.click(display: String, id: U32, x: U32, y: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
	import "./ui_native.c"
	import "./ui_native.js"

def Desktop.close(display: String, id: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
	import "./ui_native.c"
	import "./ui_native.js"

def Desktop.alive(display: String, id: U32) -> IO(Result<&1, &1, U32 & String, Bool>):
	import "./ui_native.c"
	import "./ui_native.js"
