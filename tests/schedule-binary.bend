import Base
import ../src/schedule_binary.bend as B
import ../src/schedule_file.bend as Files
import ./schedule-test-io.bend as T

type PolicyCase is Data:
  PolicyCase{label: String, bytes: List<&2,U32>, count: U32, warmup: U32, code: U32, output: String}

def prefix() -> List<&2,U32>: [0,0,0,0,3,0,0,0,1,0,0,0,2,0,0,0,2,0,0,0,1,0,0,0,2,0,0,0,4,0,0,0]
def startup() -> List<&2,U32>: [0,0,0,0,0,0,0,0]
def ordinary() -> List<&2,U32>: [2,0,0,0,0,0,0,0]
def repeat(n: Nat, bytes: List<&2,U32>) -> List<&2,U32>:
  List.concat(&2,U32,List.replicate(List<&2,U32>,n,bytes))

def policy.cases(+root: String, cases: List<&2,PolicyCase>) -> IO(Unit):
  match cases:
    case Nil{}: IO.pure(Unit,Unit{})
    case PolicyCase{label,bytes,count,warmup,code,out} <> rest:
      do IO<Unit>:
        _ : Unit <- Files.write(root ++ "/policy.bin",bytes)
        _ : Unit <- T.process("build/native-schedule-policy-tests",[root ++ "/policy.bin",U32.show(count),U32.show(warmup)],code,out,"",label)
        policy.cases(root,rest)

def damaged.row(+at: Nat, bytes: List<&2,U32>) -> PolicyCase:
  PolicyCase{"invalid phase or flags",List.concat(&2,U32,[List.take(&2,U32,prefix(),at),bytes,List.drop(&2,U32,prefix(),Nat.add(at,8n))]),4,1,2,""}

def native(+root: String) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- policy.cases(root,[
      PolicyCase{"literal prefix",prefix(),4,1,0,"0\t3\n1\t2\n2\t1\n2\t4\n"},
      PolicyCase{"support event frames",List.concat(&2,U32,[startup(),repeat(120n,[1,0,0,0,0,0,0,0]),[3,0,0,0,3,0,0,0],
        repeat(30n,ordinary()),[4,0,0,0,2,0,0,0],repeat(11n,ordinary()),[2,0,0,0,1,0,0,0]]),165,120,0,
        "0\t0\n" ++ String.repeat("1\t0\n",120n) ++ "3\t3\n" ++ String.repeat("2\t0\n",30n) ++ "4\t2\n" ++ String.repeat("2\t0\n",11n) ++ "2\t1\n"},
      PolicyCase{"zero warmup edit and motion",[0,0,0,0,0,0,0,0,3,0,0,0,7,0,0,0,4,0,0,0,5,0,0,0],3,0,0,"0\t0\n3\t7\n4\t5\n"},
      PolicyCase{"minimum frames",startup(),1,0,0,"0\t0\n"},
      PolicyCase{"maximum frames",List.append(&2,U32,startup(),repeat(21720n,ordinary())),21721,0,0,"0\t0\n" ++ String.repeat("2\t0\n",21720n)},
      damaged.row(16n,[5,0,0,0,1,0,0,0]),damaged.row(16n,[2,0,0,0,8,0,0,0]),
      damaged.row(16n,[2,0,0,128,1,0,0,0]),damaged.row(16n,[2,0,0,0,1,0,0,128]),
      damaged.row(16n,[0,0,0,2,1,0,0,0]),damaged.row(0n,[1,0,0,0,3,0,0,0]),
      damaged.row(8n,[2,0,0,0,2,0,0,0]),damaged.row(8n,[3,0,0,0,2,0,0,0]),
      damaged.row(16n,[0,0,0,0,1,0,0,0]),damaged.row(16n,[1,0,0,0,1,0,0,0]),
      PolicyCase{"zero count",prefix(),0,0,2,""},PolicyCase{"overlong count",prefix(),21722,1,2,""},
      PolicyCase{"overflow count",prefix(),4294967295,1,2,""},PolicyCase{"warmup count",prefix(),4,4,2,""},
      PolicyCase{"warmup above count",prefix(),4,5,2,""},PolicyCase{"overflow warmup",prefix(),4,4294967295,2,""},
      PolicyCase{"minimum warmup",prefix(),1,1,2,""},PolicyCase{"empty policy",[],4,1,2,""},
      PolicyCase{"partial first row",List.take(&2,U32,prefix(),7n),4,1,2,""},
      PolicyCase{"missing row",List.take(&2,U32,prefix(),24n),4,1,2,""},
      PolicyCase{"partial final row",List.take(&2,U32,prefix(),31n),4,1,2,""},
      PolicyCase{"trailing byte",List.append(&2,U32,prefix(),[0]),4,1,2,""},
      PolicyCase{"extra row",List.append(&2,U32,prefix(),ordinary()),4,1,2,""}])
    T.process("build/native-schedule-policy-tests",[root ++ "/missing","4","1"],2,"","","missing policy")

def exact(result: Result<&2,&2,String,List<&2,U32>>, expected: List<&2,U32>, label: String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,label ++ ": " ++ message)
    case Done{bytes}: T.check(T.bytes.same(bytes,expected),label)

def literals() -> IO(Unit):
  +words = {"0x80000000 0x00000000 0x3f800000 0xbf000000 0x7fc12345" : String}
  +bytes = {[0,0,0,128,0,0,0,0,0,0,128,63,0,0,0,191,69,35,193,127] : List<&2,U32>}
  do IO<Unit>:
    _ : Unit <- exact(B.request("megascene-binary/1 camera 1 row " ++ words ++ " complete"),bytes,"literal camera bits")
    _ : Unit <- exact(B.request("megascene-binary/1 ray 1 row true " ++ words ++ " 0x01020304 complete"),
      List.concat(&2,U32,[[1,0,0,0],bytes,[4,3,2,1]]),"literal ray bits")
    _ : Unit <- exact(B.request("megascene-binary/1 policy 5 row startup 3 row warmup 2 row ordinary 1 row edit 4 row motion 7 complete"),
      [0,0,0,0,3,0,0,0,1,0,0,0,2,0,0,0,2,0,0,0,1,0,0,0,3,0,0,0,4,0,0,0,4,0,0,0,7,0,0,0],"literal policy bits")
    exact(B.request("megascene-binary/1 supplementary 1 row 21720 none " ++ words ++ " complete"),
      List.concat(&2,U32,[[216,84,0,0,255,255,255,255],bytes]),"literal supplementary bits")

def invoke(+root: String, text: String, expected: U32, bytes: List<&2,U32>) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- T.text.write(root ++ "/request",text)
    _ : Unit <- T.text.write(root ++ "/output","preserved output")
    _ : Unit <- T.process("build/schedule-binary-generator",["--threads","1","--",root ++ "/request",root ++ "/output"],expected,"","","binary transport status")
    T.bytes.check(root ++ "/output",bytes,"binary output bytes")

def invalids(+root: String, texts: List<&2,String>) -> IO(Unit):
  match texts:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        _ : Unit <- invoke(root,text,2,T.text.bytes("preserved output"))
        invalids(root,rest)

def transport(+root: String) -> IO(Unit):
  +words = String.repeat("0x00000000 ",5n)
  do IO<Unit>:
    _ : Unit <- invalids(root,[
      "megascene-binary/2 camera 1 row " ++ words ++ "complete","megascene-binary/1 unknown 1 row " ++ words ++ "complete",
      "megascene-binary/1 camera 0 row " ++ words ++ "complete","megascene-binary/1 camera 21722 row " ++ words ++ "complete",
      "megascene-binary/1 camera 01 row " ++ words ++ "complete","megascene-binary/1 camera 1 row " ++ words,
      "megascene-binary/1 camera 1 row " ++ words ++ "complete extra","megascene-binary/1 camera 1 " ++ words ++ "complete",
      "megascene-binary/1 camera 1 row 0x0000000 " ++ String.repeat("0x00000000 ",4n) ++ "complete",
      "megascene-binary/1 camera 1 row 0xFFFFFFFF " ++ String.repeat("0x00000000 ",4n) ++ "complete",
      "megascene-binary/1 camera 1 row 0X00000000 " ++ String.repeat("0x00000000 ",4n) ++ "complete",
      "megascene-binary/1 policy 1 row startup 8 complete","megascene-binary/1 ray 1 row 1 " ++ words ++ "0x00000000 complete",
      "megascene-binary/1 policy 1 row unknown 0 complete","megascene-binary/1 supplementary 1 row 21721 none " ++ words ++ "complete",
      "megascene-binary/1 ray 1 row false " ++ words ++ "complete","megascene-binary/1 policy 1 row startup complete",
      "megascene-binary/1 policy 1 row startup 0 complete row ordinary 0","megascene-binary/1 camera 1  row " ++ words ++ "complete",
      "megascene-binary/1 supplementary 1 row 0 4294967296 " ++ words ++ "complete",
      "megascene-binary/1 supplementary 2 row 1 none " ++ words ++ "row 1 none " ++ words ++ "complete",
      "megascene-binary/1 supplementary 129 complete","megascene-binary/1 camera 2 row " ++ words ++ "0x00000000 row " ++ String.repeat("0x00000000 ",4n) ++ "complete",
      "",String.repeat("x",2097153n)])
    _ : Unit <- T.text.write(root ++ "/output","preserved output")
    _ : Unit <- T.process("build/schedule-binary-generator",["--threads","1","--",root ++ "/absent",root ++ "/output"],2,"","","missing binary input")
    _ : Unit <- T.bytes.check(root ++ "/output",T.text.bytes("preserved output"),"missing input preserved output")
    _ : Unit <- invoke(root,"megascene-binary/1 camera 1 row 0x80000000 0x00000000 0x3f800000 0xbf000000 0x7fc12345 complete",0,
      [0,0,0,128,0,0,0,0,0,0,128,63,0,0,0,191,69,35,193,127])
    invoke(root,"megascene-binary/1 ray 21721 " ++ String.repeat("row false " ++ String.repeat("0x00000000 ",6n),21721n) ++ "complete",0,
      List.replicate(U32,608188n,0))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> +root <> Nil{}:
      do IO<Unit>:
        _ : Unit <- native(root)
        _ : Unit <- literals()
        _ : Unit <- transport(root)
        IO.print("ALL BEND BINARY AND NATIVE POLICY CONTRACTS PASSED")
    case _: IO.die(Unit,1,"expected owned fixture directory")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
