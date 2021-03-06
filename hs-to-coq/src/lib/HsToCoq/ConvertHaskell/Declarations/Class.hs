{-# LANGUAGE RecordWildCards, LambdaCase, FlexibleContexts #-}

module HsToCoq.ConvertHaskell.Declarations.Class (ClassBody(..), convertClassDecl, getImplicitBindersForClassMember) where

import Control.Lens

import Data.Traversable
import qualified Data.List.NonEmpty as NE

import Control.Monad

import qualified Data.Map.Strict as M

import GHC hiding (Name)
import qualified GHC
import Bag
import Class

import HsToCoq.Coq.Gallina as Coq
import HsToCoq.Coq.FreeVars

import HsToCoq.ConvertHaskell.Monad
import HsToCoq.ConvertHaskell.InfixNames
import HsToCoq.ConvertHaskell.Variables
import HsToCoq.ConvertHaskell.Definitions
import HsToCoq.ConvertHaskell.Type
import HsToCoq.ConvertHaskell.Expr
import HsToCoq.ConvertHaskell.Sigs
import HsToCoq.ConvertHaskell.Declarations.Notations

--------------------------------------------------------------------------------

data ClassBody = ClassBody ClassDefinition [Notation]
               deriving (Eq, Ord, Read, Show)

instance FreeVars ClassBody where
  freeVars (ClassBody cls nots) = binding' cls $ freeVars (NoBinding nots)

-- lookup the signature of a class member and return the list of its
-- implicit binders
getImplicitBindersForClassMember  :: ConversionMonad m => Ident -> Ident -> m [Binder]
getImplicitBindersForClassMember className memberName = do
  classDef <- use (classDefns.at className)
  case classDef of
    (Just (ClassDefinition _ _ _ sigs)) ->
        case (lookup memberName sigs) of
          Just sigType -> return $ getImplicits sigType
          Nothing -> return []
    Nothing -> return []

-- strip off any implicit binders at the beginning of a (Coq) type
getImplicits :: Term -> [Binder]
getImplicits (Forall bs t) = if length bs == length imps then imps ++ getImplicits t else imps where
    imps = NE.takeWhile (\b -> case b of
                                 Inferred Implicit _ -> True
                                 Generalized Implicit _ -> True
                                 _ -> False) bs
getImplicits _ = []

convertClassDecl :: ConversionMonad m
                 => LHsContext GHC.Name                   -- ^@tcdCtxt@    Context
                 -> Located GHC.Name                      -- ^@tcdLName@   name of the class
                 -> [LHsTyVarBndr GHC.Name]               -- ^@tcdTyVars@  class type variables
                 -> [Located (FunDep (Located GHC.Name))] -- ^@tcdFDs@     functional dependencies
                 -> [LSig GHC.Name]                       -- ^@tcdSigs@    method signatures
                 -> LHsBinds GHC.Name                     -- ^@tcdMeths@   default methods
                 -> [LFamilyDecl GHC.Name]                -- ^@tcdATs@     associated types
                 -> [LTyFamDefltEqn GHC.Name]             -- ^@tcdATDefs@  associated types defaults
                 -> m ClassBody
convertClassDecl (L _ hsCtx) (L _ hsName) ltvs fds lsigs defaults types typeDefaults = do
  unless (null       fds)          $ convUnsupported "functional dependencies"
  unless (null       types)        $ convUnsupported "associated types"
  unless (null       typeDefaults) $ convUnsupported "default associated type definitions"

  name <- freeVar hsName
  ctx  <- traverse (fmap (Generalized Coq.Implicit) . convertLType) hsCtx
  args <- convertLHsTyVarBndrs Coq.Explicit ltvs
  sigs <- binding' args $ convertLSigs lsigs

  -- ugh! doesnt work for operators
  -- memberSigs.at name ?= sigs

  defs <- fmap M.fromList $ for (bagToList defaults) $ convertTypedBinding Nothing . unLoc >=> \case
            Just (ConvertedDefinitionBinding ConvertedDefinition{..}) -> do
--                typeArgs <- getImplicitBindersForClassMember name convDefName
                pure (convDefName, maybe id Fun (NE.nonEmpty (convDefArgs)) convDefBody)
            Just (ConvertedPatternBinding    _ _)                     ->
                convUnsupported "pattern bindings in class declarations"
            Nothing                                                   ->
                convUnsupported $ "skipping a type class method in " ++ show name
  unless (null defs) $ defaultMethods.at name ?= defs

  let classDefn = (ClassDefinition name (args ++ ctx) Nothing (bimap toCoqName sigType <$> M.toList sigs))

  classDefns.at name ?= classDefn

  pure $ ClassBody classDefn
                   (concatMap (buildInfixNotations sigs <*> infixToCoq) . filter identIsOperator $ M.keys sigs)
