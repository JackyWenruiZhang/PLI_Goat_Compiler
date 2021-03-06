-- | IR code generator: generate Oz instructions using Decorated AST

module GoatCodeGenerator(runCodeGenerator) where

import           Control.Monad.State
import           Data.Monoid
import           GoatAST
import           OzInstruction
import           Text.ParserCombinators.Parsec.Pos


data Gstate = Gstate
  { regCounter :: Int, labelCounter :: Int, instructions :: Endo [Instruction]}

type Generator a = State Gstate a

runCodeGenerator :: DGoatProgram -> [Instruction]
runCodeGenerator dGoatProgram
  = let state = Gstate { regCounter = 0, labelCounter = 0, instructions = Endo ([]<>) }
        s = execState (genProgram dGoatProgram) state
    in (appEndo (instructions s)) []

----------------------------------------------
-- State Helper
----------------------------------------------

-- | append a new instruction
--   O(1) time complexity
--   idea from https://kseo.github.io/posts/2017-01-21-writer-monad.html
appendIns :: Instruction -> Generator ()
appendIns x
  = do
      st <- get
      put st{instructions = (( (instructions st) <> (Endo ([x]<>))  )) }

-- | get an unused register
getReg :: Generator Int
getReg
  = do
      st <- get
      put st{regCounter = (regCounter st) + 1}
      if (regCounter st) > 1023
        then error "Register exceed 1023"
        else return (regCounter st)

-- | return used register
--   all registers that >= n will be returned
setNextUnusedReg :: Int -> Generator ()
setNextUnusedReg n
  = do
      st <- get
      put st{regCounter = n}


-- | get an unused branch label
getLabel :: String -> Generator String
getLabel prefix
  = do
      st <- get
      put st{labelCounter = (labelCounter st) + 1}
      return $ prefix ++ show (labelCounter st)
----------------------------------------------

----------------------------------------------
-- Other Helper
----------------------------------------------

-- | get the slot size of a variable
getVarSizeByDShape :: DShape -> Int
getVarSizeByDShape (DShapeVar _)   = 1
getVarSizeByDShape (DShapeArr a)   = a
getVarSizeByDShape (DShapeMat a b) = a * b

-- | convert bool to int
boolToInt :: Bool -> Int
boolToInt True  = 1
boolToInt False = 0

-- | get the binary operator data type from AST to Oz instruction
getOzBinaryOp :: Binop -> BinaryOp
getOzBinaryOp Op_add = Add
getOzBinaryOp Op_sub = Sub
getOzBinaryOp Op_mul = Mul
getOzBinaryOp Op_div = Div
getOzBinaryOp Op_eq  = Eq
getOzBinaryOp Op_ne  = Ne
getOzBinaryOp Op_lt  = Lt
getOzBinaryOp Op_le  = Le
getOzBinaryOp Op_gt  = Gt
getOzBinaryOp Op_ge  = Ge

-- | check whether the given binary operator is logical operator
isLogicalBinop :: Binop -> Bool
isLogicalBinop Op_and = True
isLogicalBinop Op_or  = True
isLogicalBinop _      = False

----------------------------------------------

----------------------------------------------
-- Generator
----------------------------------------------
-- | generate goat program
genProgram :: DGoatProgram -> Generator ()
genProgram (DProgram mainId dProcs)
  = do
      appendIns (ICall $ "proc_" ++ (show mainId))
      appendIns (IHalt)
      mapM_ genProc dProcs


-- | generate the given procedure
genProc :: DProc -> Generator ()
genProc (DProc procId numOfParas dStmts dVarInfos slotSize)
  = do
      appendIns (ILabel $ "proc_" ++ (show procId))
      appendIns (IComment $ "code for procedure " ++ (show procId))
      appendIns (IPushStack slotSize)

      appendIns (IComment $ "load parameter")
      let paraSlotSize = numOfParas
      mapM_ (\i -> do appendIns (IStatement $ Store i i)) [0..(paraSlotSize-1)]

      appendIns (IComment $ "init variable")
      reg_int_0 <- getReg
      reg_float_0 <- getReg
      appendIns (IConstant $ ConsInt reg_int_0 0)
      appendIns (IConstant $ ConsFloat reg_float_0 0.0)
      mapM_ (\(DVarInfo slotNum dShape dBaseType) ->
              do
                -- int and bool -> 0 (reg_int_0), float -> 0.0 (reg_float_0)
                let reg_init = if dBaseType == DFloatType then reg_float_0 else reg_int_0
                let endSlotNum = slotNum + ((getVarSizeByDShape dShape) - 1)
                mapM_ (\i -> appendIns (IStatement $ Store i reg_init)) [slotNum..endSlotNum]
              ) dVarInfos
      setNextUnusedReg reg_int_0

      appendIns (IComment $ "procedure begin")
      -- statement
      mapM_ genStmt dStmts

      appendIns (IComment $ "procedure end")
      appendIns (IPopStack slotSize)
      appendIns (IReturn)

-- | add a comment with the given sourcePos
sourcePosComment :: SourcePos -> Generator ()
sourcePosComment sp
  = do
    appendIns (IComment $ "line: " ++ (show $ sourceLine sp) ++ ", column: " ++ (show $ sourceLine sp))

-- | generate the given statement
genStmt :: DStmt -> Generator ()
genStmt (DAssign sourcePos dVar dExpr)
  = do
      sourcePosComment sourcePos
      appendIns (IComment $ "stmt: assignment")
      reg0 <- getReg
      evalExpr reg0 dExpr
      saveToVar reg0 dVar
      setNextUnusedReg reg0

genStmt (DWrite sourcePos dExpr)
  = do
      sourcePosComment sourcePos
      appendIns (IComment $ "stmt: write")
      let dBaseType = getBaseType dExpr
      reg0 <- getReg
      evalExpr reg0 dExpr
      let cmd = case dBaseType of DStringType -> "print_string"
                                  DBoolType   -> "print_bool"
                                  DIntType    -> "print_int"
                                  DFloatType  -> "print_real"
      appendIns (ICall_bt cmd)
      setNextUnusedReg reg0

genStmt (DRead sourcePos dVar)
  = do
      sourcePosComment sourcePos
      appendIns (IComment $ "stmt: read")
      let (DVar _ _ dBaseType) = dVar
      let cmd = case dBaseType of DBoolType  -> "read_bool"
                                  DIntType   -> "read_int"
                                  DFloatType -> "read_real"
      appendIns (ICall_bt cmd)
      reg0 <- getReg
      saveToVar reg0 dVar
      setNextUnusedReg reg0

genStmt (DCall sourcePos procId dCallParas)
  = do
      sourcePosComment sourcePos
      appendIns (IComment $ "stmt: call" ++ (show procId))
      mapM_ (
        \x -> do
          -- get registers from 0 to (length dCallParas) - 1
          reg <- getReg
          case x of
            DCallParaVal dExpr -> evalExpr reg dExpr
            DCallParaRef dVar  -> getVarAddress reg dVar
          return ()) dCallParas

      appendIns (ICall $ "proc_" ++ (show procId))
      -- set back to 0
      setNextUnusedReg 0

genStmt (DIf sourcePos dExpr dStmts dEStmts)
  = do
      sourcePosComment sourcePos
      appendIns (IComment $ "stmt: if_condition")
      reg0 <- getReg
      label_then <- getLabel "if_"
      label_else <- getLabel "if_"
      label_end  <- getLabel "if_"

      evalExpr reg0 dExpr
      appendIns (IBranch $ Cond True reg0 label_then)
      appendIns (IBranch $ Uncond label_else)
      setNextUnusedReg reg0

      -- then case
      appendIns (ILabel $ label_then)
      appendIns (IComment $ "stmt: if_then")
      mapM_ genStmt dStmts
      appendIns (IBranch $ Uncond label_end)

      -- else case
      appendIns (ILabel $ label_else)
      appendIns (IComment $ "stmt: if_else")
      mapM_ genStmt dEStmts
      appendIns (IBranch $ Uncond label_end)

      appendIns (ILabel $ label_end)
      appendIns (IComment $ "stmt: if_end")

genStmt (DWhile sourcePos dExpr dStmts)
  = do
      sourcePosComment sourcePos
      label_cond <- getLabel "while_"
      label_end  <- getLabel "while_"

      appendIns (ILabel $ label_cond)
      appendIns (IComment $ "stmt: while")

      -- guard
      reg0 <- getReg
      evalExpr reg0 dExpr
      appendIns (IBranch $ Cond False reg0 label_end)
      setNextUnusedReg reg0

      -- while body
      appendIns (IComment $ "stmt: while_body")
      mapM_ genStmt dStmts
      appendIns (IBranch $ Uncond label_cond)

      -- after while
      appendIns (ILabel $ label_end)
      appendIns (IComment $ "stmt: while_end")

-- save the value in the given register to a variable
saveToVar :: Int -> DVar -> Generator ()
-- normal scalar
saveToVar tReg (DVar slotNum (DIdxVar False) _)
  = appendIns (IStatement $ Store slotNum tReg)
-- array matrix or reference
saveToVar tReg dVar
  = do
      addrReg <- getReg
      getVarAddress addrReg dVar
      appendIns (IStatement $ Store_in addrReg tReg)
      setNextUnusedReg addrReg


-- load value from a given variable
loadFromVar :: Int -> DVar -> Generator()
-- normal scalar
loadFromVar tReg (DVar slotNum (DIdxVar False) _)
  = appendIns (IStatement $ Load tReg slotNum)
-- array matrix or reference
loadFromVar tReg dVar
  = do
      r0 <- getReg
      getVarAddress r0 dVar
      appendIns (IStatement $ Load_in tReg r0)
      setNextUnusedReg r0

-- get the address of a given variable
getVarAddress :: Int -> DVar -> Generator ()
-- scalar
getVarAddress tReg (DVar slotNum (DIdxVar isAddress) _)
  = do if isAddress
          then appendIns (IStatement $ Load tReg slotNum)
          else appendIns (IStatement $ Load_ad tReg slotNum)
-- array
getVarAddress tReg (DVar slotNum (DIdxArr dExpr) _)
  = do
      appendIns (IStatement $ Load_ad tReg slotNum)
      offsetReg <- getReg
      evalExpr offsetReg dExpr
      appendIns (IOperation $ Sub_off tReg tReg offsetReg)
      setNextUnusedReg offsetReg
-- matrix
getVarAddress tReg (DVar slotNum (DIdxMat dExpr1 dExpr2 secDimSize) _)
  = do
      appendIns (IStatement $ Load_ad tReg slotNum)
      -- dExpr1 * secDimSize + dExpr2
      offsetReg <- getReg
      evalExpr offsetReg dExpr1
      tmpReg <- getReg
      -- *
      appendIns (IConstant $ ConsInt tmpReg secDimSize)
      appendIns (IOperation $ Binary Mul INT offsetReg offsetReg tmpReg)
      -- +
      evalExpr tmpReg dExpr2
      appendIns (IOperation $ Binary Add INT offsetReg offsetReg tmpReg)
      --
      appendIns (IOperation $ Sub_off tReg tReg offsetReg)
      setNextUnusedReg offsetReg


-- evaluate the given expression and save the result to a register
evalExpr :: Int -> DExpr -> Generator ()
evalExpr tReg (DBoolConst v)
  = appendIns (IConstant $ ConsInt tReg $ boolToInt v)

evalExpr tReg (DIntConst v)
  = appendIns (IConstant $ ConsInt tReg v)

evalExpr tReg (DFloatConst v)
  = appendIns (IConstant $ ConsFloat tReg v)

evalExpr tReg (DStrConst v)
  = appendIns (IConstant $ ConsString tReg v)

evalExpr tReg (DIntToFloat e0)
  = do
      evalExpr tReg e0
      appendIns (IOperation $ Int2real tReg tReg)

evalExpr tReg (DEvar dVar)
  = loadFromVar tReg dVar

evalExpr tReg (DBinaryOp binop e0 e1 dBaseType)
  = do
      r0 <- getReg
      evalExpr tReg e0

      if isLogicalBinop binop == True
        then do
          l0 <- getLabel "bool_op_"

          -- short circuit
          if binop == Op_and
            then do
              appendIns (IComment $ "logical operation AND")
              -- if first expression in a AND operation is evaluated as false
              -- jump to the end of the evaluation process
              appendIns (IBranch $ Cond False tReg l0)
              evalExpr r0 e1
              appendIns (IOperation $ And_ tReg tReg r0)
            else do
              -- if first expression in a OR operation is evaluated as true
              -- jump to the end of the evaluation process
              appendIns (IComment $ "logical operation OR")
              appendIns (IBranch $ Cond True tReg l0)
              evalExpr r0 e1
              appendIns (IOperation $ Or_ tReg tReg r0)

          appendIns (ILabel $ l0)
        else do
          -- other binary operations other than logical opeartion
          evalExpr r0 e1
          appendIns (IOperation $ Binary (getOzBinaryOp binop)
            (getIntOrReal $ getBaseType e1) tReg tReg r0)

      setNextUnusedReg r0

evalExpr tReg (DUnaryMinus e0 dBaseType)
  = do
      evalExpr tReg e0
      appendIns (IOperation $ Unary NEG (getIntOrReal dBaseType) tReg tReg)

evalExpr tReg (DUnaryNot e0 _)
  = do
      evalExpr tReg e0
      appendIns (IOperation $ Not_ tReg tReg)

-- | Get the register type based on the type
getIntOrReal :: DBaseType -> RegType
getIntOrReal DFloatType = REAL
getIntOrReal _          = INT

-- | convert int to float in Oz instruction
genIntToFloat :: Int -> DExpr -> Generator ()
genIntToFloat r e
  = do
      if (getBaseType e) == DIntType
        then appendIns (IOperation $ Int2real r r)
      else return ()

----------------------------------------------
