-- | Data structure for the (Decorated) Abstract Syntax Tree
--
-- Authors:
--   Weizhi Xu  (752454)
--   Zijun Chen (813190)
--   Zhe Tang   (743398)

module GoatAST where

import           Text.Parsec.Pos
type Ident = String

data BaseType
  = BoolType | IntType | FloatType
    deriving (Show, Eq)

-- | for variable declaration
data Shape
  = ShapeVar
  | ShapeArr Int
  | ShapeMat Int Int
    deriving (Show, Eq)

-- | for variable index
data Idx
  = IdxVar
  | IdxArr Expr
  | IdxMat Expr Expr
    deriving (Show, Eq)

data Var
  = Var SourcePos Ident Idx
    deriving (Show, Eq)

data Binop
  = Op_add
  | Op_sub
  | Op_mul
  | Op_div
  | Op_eq
  | Op_ne
  | Op_lt
  | Op_le
  | Op_gt
  | Op_ge
  | Op_and
  | Op_or
    deriving (Show, Eq)

data Expr
  = BoolConst SourcePos Bool
  | IntConst SourcePos Int
  | FloatConst SourcePos Float
  | StrConst SourcePos String
  | Evar SourcePos Var
  | BinaryOp SourcePos Binop Expr Expr -- Binary Operator
  | UnaryMinus SourcePos Expr -- Unary operator
  | UnaryNot SourcePos Expr
    deriving (Show, Eq)

data Stmt
  = Assign SourcePos Var Expr
  | Read SourcePos Var
  | Write SourcePos Expr
  | Call SourcePos Ident [Expr]
  | If SourcePos Expr [Stmt] [Stmt]
  | While SourcePos Expr [Stmt]
    deriving (Show, Eq)

data Decl
  = Decl SourcePos Ident BaseType Shape
    deriving (Show, Eq)

data Indi
  = InVal | InRef
    deriving (Show, Eq)

data Para
  = Para SourcePos Ident BaseType Indi
    deriving (Show, Eq)

data Proc
  = Proc SourcePos Ident [Para] [Decl] [Stmt]
    deriving (Show, Eq)

data GoatProgram
  = Program [Proc]
    deriving (Show, Eq)

-- | get the sourcePos of a given Expr
getExprSourcePos :: Expr -> SourcePos
getExprSourcePos (BoolConst sourcePos _)    = sourcePos
getExprSourcePos (IntConst sourcePos _)     = sourcePos
getExprSourcePos (FloatConst sourcePos _)   = sourcePos
getExprSourcePos (StrConst sourcePos _)     = sourcePos
getExprSourcePos (Evar sourcePos _)         = sourcePos
getExprSourcePos (UnaryMinus sourcePos _)   = sourcePos
getExprSourcePos (UnaryNot sourcePos _)     = sourcePos
getExprSourcePos (BinaryOp sourcePos _ _ _) = sourcePos

--------------------------------------------------
--  Decorated Asbtract Syntax Tree
--------------------------------------------------
type SlotNum = Int
type SlotSize = Int
type ProcId = Int
type SecDimSize = Int
type NumOfParas = Int
type IsAddress = Bool

data DBaseType
  = DBoolType | DIntType | DFloatType | DStringType
    deriving (Show, Eq)

-- | for variable index
data DIdx
  = DIdxVar IsAddress
  | DIdxArr DExpr
  | DIdxMat DExpr DExpr SecDimSize
    deriving (Show, Eq)

data DShape
  = DShapeVar IsAddress
  | DShapeArr Int
  | DShapeMat Int Int
    deriving (Show, Eq)

data DVarInfo
  = DVarInfo SlotNum DShape DBaseType
    deriving (Show, Eq)

data DVar
  = DVar SlotNum DIdx DBaseType
    deriving (Show, Eq)

data DExpr
  = DBoolConst Bool
  | DIntConst Int
  | DFloatConst Float
  | DStrConst String
  | DIntToFloat DExpr
  | DEvar DVar
  | DBinaryOp Binop DExpr DExpr DBaseType -- Binary Operator
  | DUnaryMinus DExpr DBaseType -- Unary operator
  | DUnaryNot DExpr DBaseType
    deriving (Show, Eq)

data DStmt
  = DAssign SourcePos DVar DExpr
  | DRead SourcePos DVar
  | DWrite SourcePos DExpr
  | DCall SourcePos ProcId [DCallPara]
  | DIf SourcePos DExpr [DStmt] [DStmt]
  | DWhile SourcePos DExpr [DStmt]
    deriving (Show, Eq)

data DCallPara
  = DCallParaVal DExpr
  | DCallParaRef DVar
    deriving (Show, Eq)

data DProc
  = DProc ProcId NumOfParas [DStmt] [DVarInfo] SlotSize
    deriving (Show, Eq)

data DGoatProgram
  = DProgram ProcId [DProc] -- ProcId -> the procId of the main procedure
    deriving (Show, Eq)

data DProcProto
  = DProcProto ProcId [DProcProtoPara]

data DProcProtoPara
  = DProcProtoPara Indi DBaseType
    deriving (Show, Eq)

-- | get the base type of a given DExpr
getBaseType :: DExpr -> DBaseType
getBaseType (DBoolConst bool)            = DBoolType
getBaseType (DIntConst int)              = DIntType
getBaseType (DFloatConst float)          = DFloatType
getBaseType (DStrConst string)           = DStringType
getBaseType (DEvar (DVar _ _ dBaseType)) = dBaseType
getBaseType (DBinaryOp _ _ _ dBaseType)  = dBaseType
getBaseType (DUnaryMinus _ dBaseType)    = dBaseType
getBaseType (DUnaryNot _ dBaseType)      = dBaseType
getBaseType (DIntToFloat dExpr)          = DFloatType
