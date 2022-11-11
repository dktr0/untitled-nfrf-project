module Value where

import Prelude (identity, ($), show, (/=), class Semiring, class Ring, (/), (+), (-), (*), pure, (<>), bind, (>>=), map)
import Data.Int (toNumber,floor)
import Data.Map (Map, lookup, insert, fromFoldable)
import Data.Maybe (maybe,Maybe(..))
import Data.Tuple (Tuple(..))
import Data.Either (Either)
import Data.List (List)
import Parsing (ParseError(..),Position)
import Control.Monad.Error.Class (throwError)
import Data.Foldable (foldl)

import AST (Expression)
import AST as AST
import Variable

data Value =
  ValueNumber Number |
  ValueString String |
  ValueInt Int |
  ValueBoolean Boolean |
  ValueVariable Variable |
  ValueTransformer Transformer |
  ValueDancer Transformer |
  ValueFloor Transformer |
  ValueCamera Transformer

valueToNumber :: Value -> Number
valueToNumber (ValueNumber x) = x
valueToNumber (ValueInt x) = toNumber x
valueToNumber (ValueBoolean true) = 1.0
valueToNumber (ValueBoolean false) = 0.0
valueToNumber _ = 0.0

valueToString :: Value -> String
valueToString (ValueNumber x) = show x
valueToString (ValueString x) = x
valueToString (ValueInt x) = show x
valueToString (ValueBoolean x) = show x
valueToString _ = ""

valueToInt :: Value -> Int
valueToInt (ValueNumber x) = floor x
valueToInt (ValueInt x) = x
valueToInt (ValueBoolean true) = 1
valueToInt (ValueBoolean false) = 0
valueToInt _ = 0

valueToBoolean :: Value -> Boolean
valueToBoolean (ValueNumber x) = x /= 0.0
valueToBoolean (ValueString "true") = true
valueToBoolean (ValueInt x) = x /= 0
valueToBoolean (ValueBoolean x) = x
valueToBoolean _ = false

valueToVariable :: Value -> Variable
valueToVariable (ValueNumber x) = constantVariable x
valueToVariable (ValueInt x) = constantVariable $ toNumber x
valueToVariable (ValueBoolean true) = constantVariable 1.0
valueToVariable (ValueVariable x) = x
valueToVariable _ = constantVariable 0.0

valueToTransformer :: Value -> Transformer
valueToTransformer (ValueTransformer x) = x
valueToTransformer _ = pure

instance Semiring Value where
  add (ValueNumber x) y = ValueNumber $ x + valueToNumber y
  add x (ValueNumber y) = ValueNumber $ valueToNumber x + y
  add x y = ValueInt $ valueToInt x + valueToInt y
  zero = ValueInt 0
  mul (ValueNumber x) y = ValueNumber $ x * valueToNumber y
  mul x (ValueNumber y) = ValueNumber $ valueToNumber x * y
  mul x y = ValueInt $ valueToInt x * valueToInt y
  one = ValueInt 1

instance Ring Value where
  sub (ValueNumber x) y = ValueNumber $ x - valueToNumber y
  sub x (ValueNumber y) = ValueNumber $ valueToNumber x - y
  sub x y = ValueInt $ valueToInt x - valueToInt y

divideValues :: Value -> Value -> Value
divideValues x y = ValueNumber $ f (valueToNumber x) (valueToNumber y)
  where
    f _ 0.0 = 0.0
    f a b = a/b


-- ValueMap

type ValueMap = Map String Value

lookupNumber :: Number -> String -> ValueMap -> Number
lookupNumber d k m = valueToNumber $ lookupValue (ValueNumber d) k m

lookupString :: String -> String -> ValueMap -> String
lookupString d k m = valueToString $ lookupValue (ValueString d) k m

lookupInt :: Int -> String -> ValueMap -> Int
lookupInt d k m = valueToInt $ lookupValue (ValueInt d) k m

lookupBoolean :: Boolean -> String -> ValueMap -> Boolean
lookupBoolean d k m = valueToBoolean $ lookupValue (ValueBoolean d) k m

lookupVariable :: Variable -> String -> ValueMap -> Variable
lookupVariable d k m = valueToVariable $ lookupValue (ValueVariable d) k m

lookupValue :: Value -> String -> ValueMap -> Value
lookupValue d k m = maybe d identity $ lookup k m


-- parsing from AST to Values

expressionToValue :: ValueMap -> ValueMap -> Expression -> Either ParseError Value
expressionToValue _ _ (AST.LiteralNumber _ x) = pure $ ValueNumber x
expressionToValue _ _ (AST.LiteralString _ x) = pure $ ValueString x
expressionToValue _ _ (AST.LiteralInt _ x) = pure $ ValueInt x
expressionToValue _ _ (AST.LiteralBoolean _ x) = pure $ ValueBoolean x
expressionToValue _ thisMap (AST.This p k) = do
  case lookup k thisMap of
    Nothing -> throwError $ ParseError ("unknown this reference " <> k) p
    Just v -> pure v
expressionToValue semiMap _ (AST.SemiGlobal p k) = do
  case lookup k semiMap of
    Nothing -> throwError $ ParseError ("unknown semiglobal reference " <> k) p
    Just v -> pure v
expressionToValue semiMap thisMap (AST.Application p e1 e2) = applicationToValue p semiMap thisMap e1 e2
expressionToValue semiMap _ (AST.Transformer _ xs) = pure $ ValueTransformer $ realizeTransformer semiMap xs
expressionToValue _ _ (AST.Dancer _) = pure $ ValueDancer defaultDancerTransformer
expressionToValue _ _ (AST.Floor _) = pure $ ValueFloor defaultFloorTransformer
expressionToValue _ _ (AST.Camera _) = pure $ ValueCamera defaultCameraTransformer
expressionToValue _ _ (AST.Osc p) = throwError $ ParseError "Osc not re-implemented yet" p
expressionToValue _ _ (AST.Range p) = throwError $ ParseError "Osc not re-implemented yet" p
expressionToValue semiMap thisMap (AST.Sum _ e1 e2) = do
  e1' <- expressionToValue semiMap thisMap e1
  e2' <- expressionToValue semiMap thisMap e2
  pure $ e1' + e2'
expressionToValue semiMap thisMap (AST.Difference _ e1 e2) = do
  e1' <- expressionToValue semiMap thisMap e1
  e2' <- expressionToValue semiMap thisMap e2
  pure $ e1' - e2'
expressionToValue semiMap thisMap (AST.Product _ e1 e2) = do
  e1' <- expressionToValue semiMap thisMap e1
  e2' <- expressionToValue semiMap thisMap e2
  pure $ e1' * e2'
expressionToValue semiMap thisMap (AST.Divide _ e1 e2) = do
  e1' <- expressionToValue semiMap thisMap e1
  e2' <- expressionToValue semiMap thisMap e2
  pure $ divideValues e1' e2'


type Transformer = ValueMap -> Either ParseError ValueMap

realizeModifier :: ValueMap -> Tuple String Expression -> Transformer
realizeModifier semiMap (Tuple k e) thisMap = do
  v <- expressionToValue semiMap thisMap e
  pure $ insert k v thisMap

realizeTransformer :: ValueMap -> (List (Tuple String Expression)) -> Transformer
realizeTransformer semiMap xs = foldl appendTransformers pure $ map (realizeModifier semiMap) xs

appendTransformers :: Transformer -> Transformer -> Transformer
appendTransformers fx fy = \thisMap -> fx thisMap >>= fy

defaultDancerTransformer :: Transformer
defaultDancerTransformer = pure $ pure $ fromFoldable [
  Tuple "x" (ValueNumber 0.0),
  Tuple "y" (ValueNumber 0.0),
  Tuple "z" (ValueNumber 0.0),
  Tuple "rx" (ValueNumber 0.0),
  Tuple "ry" (ValueNumber 0.0),
  Tuple "rz" (ValueNumber 0.0),
  Tuple "sx" (ValueNumber 1.0),
  Tuple "sy" (ValueNumber 1.0),
  Tuple "sz" (ValueNumber 1.0),
  Tuple "size" (ValueNumber 1.0)
  ]

defaultFloorTransformer :: Transformer
defaultFloorTransformer = pure $ pure $ fromFoldable [
  Tuple "colour" (ValueInt 0x888888),
  Tuple "shadows" (ValueBoolean true)
  ]

defaultCameraTransformer :: Transformer
defaultCameraTransformer = pure $ pure $ fromFoldable [
  Tuple "x" (ValueNumber 0.0),
  Tuple "y" (ValueNumber 1.0),
  Tuple "z" (ValueNumber 10.0),
  Tuple "rx" (ValueNumber 0.0),
  Tuple "ry" (ValueNumber 0.0),
  Tuple "rz" (ValueNumber 0.0)
  ]

applicationToValue :: Position -> ValueMap -> ValueMap -> Expression -> Expression -> Either ParseError Value
applicationToValue p semiMap thisMap eF eX = do
  f <- expressionToValue semiMap thisMap eF
  x <- expressionToValue semiMap thisMap eX
  case f of
    ValueNumber _ -> throwError $ ParseError "A Number can't be the left side of a function application" p
    ValueString _ -> throwError $ ParseError "A String can't be the left side of a function application" p
    ValueInt _ -> throwError $ ParseError "An Int can't be the left side of a function application" p
    ValueBoolean _ -> throwError $ ParseError "A Boolean can't be the left side of a function application" p
    ValueVariable _ -> throwError $ ParseError "A Variable can't be the left side of a function application" p
    ValueTransformer tF -> do
      case x of
        ValueTransformer tX -> pure $ ValueTransformer $ appendTransformers tF tX
        ValueDancer tX -> pure $ ValueDancer $ appendTransformers tX tF -- note reverse application when transformers are on left of dancers/floor/camera
        ValueFloor tX -> pure $ ValueFloor $ appendTransformers tX tF
        ValueCamera tX -> pure $ ValueCamera $ appendTransformers tX tF
        _ -> throwError $ ParseError "invalid argument applied to Transformer" (AST.expressionPosition eX)
    ValueDancer tF -> do
      case x of
        ValueTransformer tX -> pure $ ValueDancer $ appendTransformers tF tX
        ValueDancer tX -> pure $ ValueDancer $ appendTransformers tF tX
        _ -> throwError $ ParseError "invalid argument applied to Dancer" (AST.expressionPosition eX)
    ValueCamera tF -> do
      case x of
        ValueTransformer tX -> pure $ ValueCamera $ appendTransformers tF tX
        ValueCamera tX -> pure $ ValueCamera $ appendTransformers tF tX
        _ -> throwError $ ParseError "invalid argument applied to Camera" (AST.expressionPosition eX)
    ValueFloor tF -> do
      case x of
        ValueTransformer tX -> pure $ ValueFloor $ appendTransformers tF tX
        ValueFloor tX -> pure $ ValueFloor $ appendTransformers tF tX
        _ -> throwError $ ParseError "invalid argument applied to Floor" (AST.expressionPosition eX)
