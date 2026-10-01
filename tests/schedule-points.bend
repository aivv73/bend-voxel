import Base
import ../src/schedule_points.bend as P
import ./schedule-test-io.bend as T

def serialized(result: Result<&2,&2,String,String>, expected: String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{text}: T.check(String.eq(text,expected),"checkpoint bytes differ")

def rejected(result: Result<&2,&2,String,String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.pure(Unit,Unit{})
    case Done{_}: IO.die(Unit,1,"accepted invalid checkpoint transport")

def args(n: Nat, +i: U32) -> List<String>:
  match n:
    case 0n: Nil{}
    case 1n+p: "21720" <> ("p" ++ U32.show(i)) <> args(p,(i + 1 : U32))

def expected(n: Nat, +i: U32) -> String:
  match n:
    case 0n: ""
    case 1n+p: "21720\tp" ++ U32.show(i) ++ "\n" ++ expected(p,(i + 1 : U32))

def invalids(xs: List<&2,List<&2,String>>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit,Unit{})
    case row <> rest:
      do IO<Unit>:
        _ : Unit <- rejected(P.serialize("megascene-checkpoints/1","2",T.linear(row)))
        invalids(rest)

def serializer() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- serialized(P.serialize("megascene-checkpoints/1","3",["2","finish","0","z_start","0","a_start"]),
      "megascene-checkpoints/1\t3\t3\n0\tz_start\n0\ta_start\n2\tfinish\n")
    _ : Unit <- serialized(P.serialize("megascene-reviews/1","3",["0","opening"]),"megascene-reviews/1\t3\t1\n0\topening\n")
    _ : Unit <- invalids([["2","outside"],["0","bad name"],["0","same","1","same"],[],["0"],
      ["00","name"],["4294967296","name"],["0","name","extra"],["0",String.repeat("n",129n)]])
    _ : Unit <- rejected(P.serialize("megascene-checkpoints/2","2",["0","name"]))
    _ : Unit <- rejected(P.serialize("megascene-checkpoints/1","21722",["0","name"]))
    _ : Unit <- rejected(P.serialize("megascene-checkpoints/1","21721",args(4097n,0)))
    _ : Unit <- serialized(P.serialize("megascene-checkpoints/1","1",["0",String.repeat("n",128n)]),
      "megascene-checkpoints/1\t1\t1\n0\t" ++ String.repeat("n",128n) ++ "\n")
    serialized(P.serialize("megascene-checkpoints/1","21721",args(4096n,0)),
      "megascene-checkpoints/1\t21721\t4096\n" ++ expected(4096n,0))

def cli(cases: List<&2,List<&2,String>>) -> IO(Unit):
  match cases:
    case Nil{}: IO.pure(Unit,Unit{})
    case args <> rest:
      do IO<Unit>:
        _ : Unit <- T.process("build/schedule-points-generator",T.linear(List.append(&2,String,["--threads","1","--"],args)),
          2,"","","invalid points CLI")
        cli(rest)

def native(+root: String, text: String, review: String, frame: String, measured: String, expected: U32, output: String, error: String) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- T.text.write(root ++ "/points.tsv",text)
    T.process("env",["-u","MEGASCENE_CHECKPOINT_FILE","-u","MEGASCENE_REVIEW_FILE",
      "MEGASCENE_CHECKPOINT_FILE=" ++ root ++ "/points.tsv","MEGASCENE_REVIEW_FILE=" ++ root ++ "/points.tsv",
      "build/native-schedule-points-tests",review,frame,"0",measured],expected,output,error,"native points")

def damaged(+root: String, texts: List<&2,String>) -> IO(Unit):
  match texts:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        _ : Unit <- native(root,text,"0","0","1",2,"","checkpoint plan")
        damaged(root,rest)

def readers(+root: String) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- native(root,"megascene-checkpoints/1\t3\t3\n0\tz_start\n0\ta_start\n2\tfinish\n","0","2","2",0,"1\n","")
    _ : Unit <- native(root,"megascene-checkpoints/1\t2\t2\n1\tinitialization\n1\tmotion_0\n","0","0","1",0,"0\n","")
    _ : Unit <- native(root,"megascene-checkpoints/1\t2\t2\n1\tinitialization\n1\tmotion_0\n","0","1","1",0,"1\n","")
    _ : Unit <- native(root,"megascene-reviews/1\t2\t1\n0\tcapture\n","1","0","1",0,"1\n","")
    _ : Unit <- native(root,"megascene-reviews/1\t2\t1\n0\tcapture\n","1","1","1",0,"0\n","")
    _ : Unit <- damaged(root,["","megascene-checkpoints/2\t2\t1\n0\tname\n",
      "megascene-checkpoints/1\t0\t1\n0\tname\n","megascene-checkpoints/1\t21722\t1\n0\tname\n",
      "megascene-checkpoints/1\t2\t0\n","megascene-checkpoints/1\t2\t4097\n","megascene-checkpoints/1\t2\t4294967296\n",
      "megascene-checkpoints/1\t3\t1\n0\tname\n","megascene-checkpoints/1\t2\t2\n0\tname\n",
      "megascene-checkpoints/1\t2\t1\n0\tname\n1\textra\n","megascene-checkpoints/1\t2\t1\n2\tname\n",
      "megascene-checkpoints/1\t2\t1\n00\tname\n","megascene-checkpoints/1\t2\t1\n-1\tname\n",
      "megascene-checkpoints/1\t2\t1\n4294967296\tname\n","megascene-checkpoints/1\t2\t2\n1\tlater\n0\tearlier\n",
      "megascene-checkpoints/1\t2\t2\n0\tname\n1\tname\n","megascene-checkpoints/1\t2\t1\n0\t\n",
      "megascene-checkpoints/1\t2\t1\n0\tbad name\n","megascene-checkpoints/1\t2\t1\n0\tname\textra\n",
      "megascene-checkpoints/1\t2\t1\n0\tname\r\n","megascene-checkpoints/1\t2\t1\n0\tname",
      "megascene-checkpoints/1\t2\t1\n0\t" ++ String.repeat("n",129n) ++ "\n"])
    _ : Unit <- T.process("env",["-u","MEGASCENE_CHECKPOINT_FILE","-u","MEGASCENE_REVIEW_FILE",
      "build/native-schedule-points-tests","0","0","0","1"],2,"","checkpoint plan","missing points")
    native(root,"megascene-checkpoints/1\t2\t1\n0\tname\n","0","2","1",2,"","frame outside frozen schedule")

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> root <> Nil{}:
      do IO<Unit>:
        _ : Unit <- serializer()
        _ : Unit <- cli([[],["megascene-checkpoints/1"],["megascene-checkpoints/2","2","0","name"],
          ["megascene-checkpoints/1","2","0"],["megascene-checkpoints/1","2"],
          ["megascene-checkpoints/1","2","00","name"],["megascene-checkpoints/1","2","4294967296","name"],
          ["megascene-checkpoints/1","2","0","name","extra"]])
        _ : Unit <- readers(root)
        IO.print("ALL BEND AND NATIVE CHECKPOINT/REVIEW CONTRACTS PASSED")
    case _: IO.die(Unit,1,"expected owned fixture directory")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
