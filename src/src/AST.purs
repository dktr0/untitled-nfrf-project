module AST (
  AST,
  Statement(..),
  Expression(..),
  ast
  ) where

import Prelude (class Show, bind, discard, pure, show, unit, ($), ($>), (<$), (<$>), (<*>), (<>))
import Data.List (List)
import Data.Tuple (Tuple(..))
import Parsing (Position,position)
import Parsing.Combinators (chainl1, choice, lookAhead, try, (<|>))
import Parsing.String (eof)

import TokenParser (P, boolean, commaSep, identifier, integer, number, parens, reserved, reservedOp, semiSep, stringLiteral, whiteSpace)


type AST = List Statement

data Statement =
  Assignment Position String Expression |
  Action Position Expression |
  EmptyStatement Position

instance Show Statement where
  show (Assignment p k e) = "Assignment (" <> show p <> ") " <> show k <> " (" <> show e <> ")"
  show (Action p e) = "Action (" <> show p <> ") (" <> show e <> ")"
  show (EmptyStatement p) = "EmptyStatement (" <> show p <> ")"

data Expression =
  LiteralNumber Position Number |
  LiteralString Position String |
  LiteralInt Position Int |
  LiteralBoolean Position Boolean |
  This Position String | -- eg. this.x would be This "x"
  SemiGlobal Position String | -- eg. x would be SemiGlobal "x"
  Application Position Expression Expression |
  Transformer Position (List (Tuple String Expression)) |
  Dancer Position | Floor Position | Camera Position | Osc Position | Range Position |
  Sum Position Expression Expression |
  Difference Position Expression Expression |
  Product Position Expression Expression |
  Divide Position Expression Expression

instance Show Expression where
  show (LiteralNumber p x) = "LiteralNumber (" <> show p <> ") " <> show x
  show (LiteralString p x) = "LiteralString (" <> show p <> ") " <> show x
  show (LiteralInt p x) = "LiteralInt (" <> show p <> ") " <> show x
  show (LiteralBoolean p x) = "LiteralBoolean (" <> show p <> ") " <> show x
  show (This p x) = "This (" <> show p <> ") " <> show x
  show (SemiGlobal p x) = "SemiGlobal (" <> show p <> ") " <> show x
  show (Application p e1 e2) = "Application (" <> show p <> ") (" <> show e1 <> ") (" <> show e2 <> ")"
  show (Transformer p x) = "Transformer (" <> show p <> ") (" <> show x <> ")"
  show (Dancer p) = "Dancer (" <> show p <> ")"
  show (Floor p) = "Floor (" <> show p <> ")"
  show (Camera p) = "Camera (" <> show p <> ")"
  show (Osc p) = "Osc (" <> show p <> ")"
  show (Range p) = "Range (" <> show p <> ")"
  show (Sum p e1 e2) = "Sum (" <> show p <> ") (" <> show e1 <> ") (" <> show e2 <> ")"
  show (Difference p e1 e2) = "Difference (" <> show p <> ") (" <> show e1 <> ") (" <> show e2 <> ")"
  show (Product p e1 e2) = "Product (" <> show p <> ") (" <> show e1 <> ") (" <> show e2 <> ")"
  show (Divide p e1 e2) = "Divide (" <> show p <> ") (" <> show e1 <> ") (" <> show e2 <> ")"


-- parsing:

ast :: P AST
ast = do
  whiteSpace
  xs <- semiSep statement
  eof
  pure $ xs

statement :: P Statement
statement = try assignment <|> try action <|> emptyStatement

assignment :: P Statement
assignment = do
  p <- position
  k <- identifier
  reservedOp "="
  v <- expression
  pure $ Assignment p k v

action :: P Statement
action = Action <$> position <*> expression

emptyStatement :: P Statement
emptyStatement = do
  p <- position
  lookAhead whiteSpace
  lookAhead eof <|> lookAhead (reservedOp ";")
  pure $ EmptyStatement p

expression :: P Expression
expression = do
  _ <- pure unit
  chainl1 expression' additionSubtraction

additionSubtraction :: P (Expression -> Expression -> Expression)
additionSubtraction = do
  p <- position
  choice [
    reservedOp "+" $> Sum p,
    reservedOp "-" $> Difference p
    ]

expression' :: P Expression
expression' = do
  _ <- pure unit
  chainl1 expression'' multiplicationDivision

multiplicationDivision :: P (Expression -> Expression -> Expression)
multiplicationDivision = do
  p <- position
  choice [
    reservedOp "*" $> Product p,
    reservedOp "/" $> Divide p
    ]

expression'' :: P Expression
expression'' = do
  _ <- pure unit
  p <- position
  choice [
    parens expression,
    try transformer,
    try application,
    try $ LiteralNumber p <$> number,
    try $ LiteralString p <$> stringLiteral,
    try $ LiteralInt p <$> integer,
    try $ LiteralBoolean p <$> boolean,
    try thisRef,
    try semiGlobalRef,
    try (Dancer p <$ reserved "dancer"),
    try (Floor p <$ reserved "floor"),
    try (Camera p <$ reserved "camera"),
    try (Osc p <$ reserved "osc"),
    try (Range p <$ reserved "range")
    ]

application :: P Expression
application = do
  _ <- pure unit
  p <- position
  e1 <- expression
  e2 <- expressionAsArgument
  pure $ Application p e1 e2

-- note: this is the same as expression'' minus the direct pathway for Application
expressionAsArgument :: P Expression
expressionAsArgument = do
  _ <- pure unit
  p <- position
  choice [
    parens expression,
    try transformer,
    try $ LiteralNumber p <$> number,
    try $ LiteralString p <$> stringLiteral,
    try $ LiteralInt p <$> integer,
    try $ LiteralBoolean p <$> boolean,
    try thisRef,
    try semiGlobalRef,
    try (Dancer p <$ reserved "dancer"),
    try (Floor p <$ reserved "floor"),
    try (Camera p <$ reserved "camera"),
    try (Osc p <$ reserved "osc"),
    try (Range p <$ reserved "range")
  ]

transformer :: P Expression
transformer = do
  _ <- pure unit
  p <- position
  reservedOp "{"
  xs <- commaSep modifier
  reservedOp "}"
  pure $ Transformer p xs

modifier :: P (Tuple String Expression)
modifier = do
  k <- identifier
  reservedOp "="
  e <- expression
  pure $ Tuple k e

thisRef :: P Expression
thisRef = do
  p <- position
  reserved "this"
  reservedOp "."
  This p <$> identifier

semiGlobalRef :: P Expression
semiGlobalRef = SemiGlobal <$> position <*> identifier
