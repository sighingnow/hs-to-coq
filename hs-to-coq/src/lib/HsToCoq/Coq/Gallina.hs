{-|
Module      : HsToCoq.Coq.Gallina
Description : An AST for Gallina, the surface language of Coq
Copyright   : Copyright © 2016 Antal Spector-Zabusky, University of Pennsylvania
License     : MIT
Maintainer  : antal.b.sz@gmail.com
Stability   : experimental

<https://coq.inria.fr/distrib/current/refman/Reference-Manual003. Chapter 1, \"The Gallina Specification Language\", in the Coq reference manual.>
-}

{-# LANGUAGE DeriveDataTypeable, OverloadedStrings, LambdaCase, TemplateHaskell #-}

module HsToCoq.Coq.Gallina (
  -- * Lexical structure
  -- $Lexical
  Ident,
  AccessIdent,
  Num,
  Op,

  -- * Terms
  -- $Terms
  Term(..),
  Arg(..),
  Binders,
  Generalizability(..),
  Explicitness(..),
  Binder(..),
  Name(..),
  Qualid(..),
  Sort(..),
  FixBodies(..),
  CofixBodies(..),
  FixBody(..),
  CofixBody(..),
  Annotation(..),
  MatchItem(..),
  DepRetType(..),
  ReturnType(..),
  Equation(..),
  MultPattern(..),
  Pattern(..),
  OrPattern(..),
  Comment(..),

  -- * Signatures
  Signature(..),

  -- * The vernacular
  -- $Vernacular
  Sentence(..),
  Assumption(..),
  AssumptionKeyword(..),
  Assums(..),
  Locality(..),
  Definition(..),
  Inductive(..),
  IndBody(..),
  Fixpoint(..),
  Assertion(..),
  AssertionKeyword(..),
  Tactics,
  Proof(..),
  ClassDefinition(..),
  InstanceDefinition(..),
  Associativity(..),
  Level(..),
  Notation(..),
  NotationBinding(..),
  Arguments(..),
  ArgumentSpec(..),
  ArgumentExplicitness(..),

  -- * Formatting
  renderGallina,
  Gallina(..),
  renderIdent, renderAccessIdent, renderNum, renderString, renderOp,
  renderLocality, renderFullLocality,
  ) where

import Prelude hiding (Num)

import Data.Foldable
import Data.Traversable
import HsToCoq.Util.Function

import Data.Text (Text)
import qualified Data.Text as T
import Numeric.Natural

import Data.List.NonEmpty (NonEmpty(), (<|), nonEmpty)

import Data.Typeable
import Data.Data (Data(..))

import HsToCoq.PrettyPrint
import qualified Language.Haskell.TH as TH

-- $Lexical
-- <https://coq.inria.fr/distrib/current/refman/Reference-Manual003.html#lexical §1.1, \"Lexical conventions\", in the Coq reference manual.>
--
-- We don't model the lexical conventions.  Values are just strings or numbers
-- or what have you.

-- |@/ident/ ::= /first_letter/ [/subsequent_letter/ … /subsequent_letter/]@
type Ident       = Text
-- |@/access_ident/ ::= . /ident/@
type AccessIdent = Ident
-- |@/num/ ::= /digit/ … /digit/@
type Num         = Natural

-- |@/op/ ::= /symbol/ [/symbol/ … /symbol/]@ /(extra)/
type Op          = Text

-- $Terms
-- <https://coq.inria.fr/distrib/current/refman/Reference-Manual003.html#term §1.2, \"Terms\", in the Coq reference manual.>

-- |NB: There is a bug in the Coq manual as regards the definition
-- of destructuring pattern-@let@, i.e. with @let ' /pattern/ …@.  The
-- definition is given as
--
-- @
-- let ' /pattern/ [in /term/] := /term/ [/return_type/] in /term/
-- @
--
-- However:
--
-- 1. The @in@ annotation will only parse if the @/return_type/@ is present; and
-- 2. The @in@ annotation should be @[in /qualid/ [/pattern/ … /pattern/]]@
--    instead of simply @[in /term/]@, just as for @/match_item/@.
--
-- I have thus implemented this change in the AST that follows (the 'LetTick'
-- and 'LetTickDep' cases).
--
-- @/term/ ::=@
data Term = Forall Binders Term                                                                -- ^@forall /binders/, /term/@
          | Fun Binders Term                                                                   -- ^@fun /binders/ => /term/@
          | Fix FixBodies                                                                      -- ^@fix /fix_bodies/@
          | Cofix CofixBodies                                                                  -- ^@cofix /cofix_bodies/@
          | Let Ident [Binder] (Maybe Term) Term Term                                          -- ^@let /ident/ [/binders/] [: /term/] := /term/ in /term/@
          | LetFix FixBody Term                                                                -- ^@let fix /fix_body/ in /term/@
          | LetCofix CofixBody Term                                                            -- ^@let cofix /cofix_body/ in /term/@
          | LetTuple [Name] (Maybe DepRetType) Term Term                                       -- ^@let ( [/name/ , … , /name/] ) [/dep_ret_type/] := /term/ in /term/@
          | LetTick Pattern Term Term                                                          -- ^@let ' /pattern/ := /term/ in /term/@
          | LetTickDep Pattern (Maybe (Qualid, [Pattern])) Term ReturnType Term                -- ^@let ' /pattern/ [in /qualid/ [/pattern/ … /pattern/]] := /term/ /return_type/ in /term/@
          | If Term (Maybe DepRetType) Term Term                                               -- ^@if /term/ [/dep_ret_type/] then /term/ else /term/@
          | HasType Term Term                                                                  -- ^@/term/ : /term/@
          | CheckType Term Term                                                                -- ^@/term/ <: /term/@
          | ToSupportType Term                                                                 -- ^@/term/ :>@
          | Arrow Term Term                                                                    -- ^@/term/ -> /term/@
          | App Term (NonEmpty Arg)                                                            -- ^@/term/ /arg/ … /arg/@
          | ExplicitApp Qualid [Term]                                                          -- ^@\@ /qualid/ [/term/ … /term/]@
          | Infix Term Op Term                                                                 -- ^@/term/ /op/ /term/@ – extra
          | InScope Term Ident                                                                 -- ^@/term/ % /ident/@
          | Match (NonEmpty MatchItem) (Maybe ReturnType) [Equation]                           -- ^@match /match_item/ , … , /match_item/ [/return_type/] with [[|] /equation/ | … | /equation/] end@
          | Qualid Qualid                                                                      -- ^@/qualid/@
          | Sort Sort                                                                          -- ^@/sort/@
          | Num Num                                                                            -- ^@/num/@
          | PolyNum Num                                                                        -- ^@# /num/@ – extra (for polymorphic number literals)
          | String Text                                                                        -- ^@/string/@ – extra (holds the value, not the source text)
          | HsString Text                                                                      -- ^@& /string/@ – extra (for Haskell string literals)
          | HsChar Char                                                                        -- ^@&# /string/@ – extra (for Haskell character literals; /string/ is a single ASCII character)
          | Underscore                                                                         -- ^@_@
          | Parens Term                                                                        -- ^@( /term/ )@
          | Bang Term                                                                          -- ^@! term - tmp suppress implicit arguments (for Instance decls)
          | MissingValue                                                                       -- ^@_@ – extra (a value we don't know how to fill in)
          deriving (Eq, Ord, Show, Read, Typeable, Data)

infixr 7 `Arrow`
infixl 8 `App`

-- |@/arg/ ::=@
data Arg = PosArg Term                                                                         -- ^@/term/@
         | NamedArg Ident Term                                                                 -- ^@( /ident/ := /term/ )@
         deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/binders/ ::= /binder/ … /binder/@
type Binders = NonEmpty Binder

-- |@/generalizability/ ::=@ – not a part of the grammar /per se/, but a common fragment
data Generalizability = Ungeneralizable                                                        -- ^@@ – (nothing)
                      | Generalizable                                                          -- ^@`@
                      deriving (Eq, Ord, Show, Read, Enum, Bounded, Typeable, Data)

-- |@/explicitness/ ::=@ – not a part of the grammar /per se/, but a common fragment
data Explicitness = Explicit                                                                   -- ^@( ⋯ )@ – wrap in parentheses
                  | Implicit                                                                   -- ^@{ ⋯ }@ – wrap in braces
                  deriving (Eq, Ord, Show, Read, Enum, Bounded, Typeable, Data)

-- |@/binder/ ::=@ – the @/explicitness/@ is extra
data Binder = Inferred Explicitness Name                                                       -- ^@/name/@ or @{ /name/ }@
            | Typed Generalizability Explicitness (NonEmpty Name) Term                         -- ^@/generalizability/@ @( /name/ … /name/ : /term/ )@ or @/generalizability/@ @{ /name/ … /name/ : /term/ }@
            | BindLet Name (Maybe Term) Term                                                   -- ^@( /name/ [: /term/] := /term/ )@
            | Generalized Explicitness Term                                                    -- ^@` ( /term/ )@ or @` { /term/ }@
            deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/name/ ::=@
data Name = Ident Ident                                                                        -- ^@/ident/@
          | UnderscoreName                                                                     -- ^@_@
          deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/qualid/ ::=@
data Qualid = Bare Ident                                                                       -- ^@/ident/@
            | Qualified Qualid AccessIdent                                                     -- ^@/qualid/ /access_ident/@
            deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/sort/ ::=@
data Sort = Prop                                                                               -- ^@Prop@
          | Set                                                                                -- ^@Set@
          | Type                                                                               -- ^@Type@
          deriving (Eq, Ord, Show, Read, Enum, Bounded, Typeable, Data)

-- |@/fix_bodies/ ::=@
data FixBodies = FixOne FixBody                                                                -- ^@/fix_body/@
               | FixMany FixBody (NonEmpty FixBody) Ident                                      -- ^@/fix_body/ with /fix_body/ with … with /fix_body/ for /ident/@
               deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/cofix_bodies/ ::=@
data CofixBodies = CofixOne CofixBody                                                          -- ^@/cofix_body/@
                 | CofixMany CofixBody (NonEmpty CofixBody) Ident                              -- ^@/cofix_body/ with /cofix_body/ with … with /cofix_body/ for /ident/@
                 deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/fix_body/ ::=@
data FixBody = FixBody Ident Binders (Maybe Annotation) (Maybe Term) Term                      -- ^@/ident/ /binders/ [/annotation/] [: /term/] := /term/@
             deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/cofix_body/ ::=@
data CofixBody = CofixBody Ident Binders (Maybe Term) Term                                     -- ^@/ident/ /binders/ [: /term/] := /term/@
               deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/annotation/ ::=@
newtype Annotation = Annotation Ident                                                          -- ^@{ struct /ident/ }@
                   deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/match_item/ ::=@
data MatchItem = MatchItem Term (Maybe Name) (Maybe (Qualid, [Pattern]))                       -- ^@/term/ [as /name/] [in /qualid/ [/pattern/ … /pattern/]]@
               deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/dep_ret_type/ ::=@
data DepRetType = DepRetType (Maybe Name) ReturnType                                           -- ^@[as /name/] /return_type/@
                deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/return_type/ ::=@
newtype ReturnType = ReturnType Term                                                           -- ^@return /term/@
                   deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/equation/ ::=@
data Equation = Equation (NonEmpty MultPattern) Term                                           -- ^@/mult_pattern/ | … | /mult_pattern/ => /term/@
              deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/mult_pattern/ ::=@
newtype MultPattern = MultPattern (NonEmpty Pattern)                                           -- ^@/pattern/ , … , /pattern/@
                    deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/pattern/ ::=@
data Pattern = ArgsPat Qualid (NonEmpty Pattern)                                               -- ^@/qualid/ /pattern/ … /pattern/@
             | ExplicitArgsPat Qualid (NonEmpty Pattern)                                       -- ^@\@ /qualid/ /pattern/ … /pattern/@
             | InfixPat Pattern Op Pattern                                                     -- ^@/pattern/ /op/ /pattern/@ – extra
             | AsPat Pattern Ident                                                             -- ^@/pattern/ as /ident/@
             | InScopePat Pattern Ident                                                        -- ^@/pattern/ % /ident/@
             | QualidPat Qualid                                                                -- ^@/qualid/@
             | UnderscorePat                                                                   -- ^@_@
             | NumPat Num                                                                      -- ^@/num/@
             | StringPat Text                                                                  -- ^@/string/@ – extra (holds the value, not the source text)
             | OrPats (NonEmpty OrPattern)                                                     -- ^@( /or_pattern/ , … , /or_pattern/ )@
             deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/or_pattern/ ::=@
newtype OrPattern = OrPattern (NonEmpty Pattern)                                               -- ^@/pattern/ | … | /pattern/@
                  deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/comment/ ::=@ /(extra)/
newtype Comment = Comment Text                                                                 -- ^@(* … *)@
                deriving (Eq, Ord, Show, Read, Typeable, Data)

-- $Vernacular
-- <https://coq.inria.fr/distrib/current/refman/Reference-Manual003.html#Vernacular §1.3, \"The Vernacular\", in the Coq reference manual.>.
--
-- We also add cases to deal with certain notation definitions and similar.

-- |@/sentence/ ::=@
data Sentence = AssumptionSentence Assumption                                                  -- ^@/assumption/@
              | DefinitionSentence Definition                                                  -- ^@/definition/@
              | InductiveSentence  Inductive                                                   -- ^@/inductive/@
              | FixpointSentence   Fixpoint                                                    -- ^@/fixpoint/@
              | AssertionSentence  Assertion Proof                                             -- ^@/assertion/ /proof/@
              | ClassSentence      ClassDefinition                                             -- ^@/class_definition/@ – extra
              | InstanceSentence   InstanceDefinition                                          -- ^@/instance_definition/@ – extra
              | NotationSentence   Notation                                                    -- ^@/notation/@ – extra
              | ArgumentsSentence  Arguments                                                   -- ^@/arguments/@ – extra
              | CommentSentence    Comment                                                     -- ^@/comment/@ – extra
              deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/assumption/ ::=@
data Assumption = Assumption AssumptionKeyword Assums                                          -- ^@/assumption_keyword/ /assums/ .@
                deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/assumption_keyword/ ::=@
data AssumptionKeyword = Axiom                                                                 -- ^@Axiom@
                       | Axioms                                                                -- ^@Axioms@ – not in the grammar, but accepted.
                       | Conjecture                                                            -- ^@Conjecture@
                       | Parameter                                                             -- ^@Parameter@
                       | Parameters                                                            -- ^@Parameters@
                       | Variable                                                              -- ^@Variable@
                       | Variables                                                             -- ^@Variables@
                       | Hypothesis                                                            -- ^@Hypothesis@
                       | Hypotheses                                                            -- ^@Hypotheses@
                       deriving (Eq, Ord, Show, Read, Enum, Bounded, Typeable, Data)

-- |@/assums/ ::=@
data Assums = UnparenthesizedAssums (NonEmpty Ident) Term                                      -- ^@/ident/ … /ident/ : /term/@
            | ParenthesizedAssums (NonEmpty (NonEmpty Ident, Term))                            -- ^@( /ident/ … /ident/ : /term ) … ( /ident/ … /ident/ : /term)@
            deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@[Local] ::=@ – not a part of the grammar /per se/, but a common fragment
data Locality = Global                                                                         -- ^@@ – (nothing – but sometimes @Global@)
              | Local                                                                          -- ^@Local@
              deriving (Eq, Ord, Show, Read, Enum, Bounded, Typeable, Data)

-- |@/definition/ ::=@
data Definition = DefinitionDef Locality Ident [Binder] (Maybe Term) Term                      -- ^@[Local] Definition /ident/ [/binders/] [: /term/] := /term/ .@
                | LetDef Ident [Binder] (Maybe Term) Term                                      -- ^@Let /ident/ [/binders/] [: /term/] := /term/ .@
                deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/inductive/ ::=@ – the @where@ notation bindings are extra
data Inductive = Inductive   (NonEmpty IndBody) [NotationBinding]                              -- ^@Inductive /ind_body/ with … with /ind_body/ [where /notation_binding/ and … and /notation_binding/] .@
               | CoInductive (NonEmpty IndBody) [NotationBinding]                              -- ^@CoInductive /ind_body/ with … with /ind_body/ [where /notation_binding/ and … and /notation_binding/] .@
               deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/ind_body/ ::=@
data IndBody = IndBody Ident [Binder] Term [(Ident, [Binder], Maybe Term)]                     -- ^@/ident/ [/binders/] : /term/ := [[|] /ident/ [/binders/] [: /term/] | … | /ident/ [/binders/] [: /term/]]@
             deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/fixpoint/ ::=@
data Fixpoint = Fixpoint   (NonEmpty FixBody)   [NotationBinding]                              -- ^@Fixpoint /fix_body/ with … with /fix_body/ [where /notation_binding/ and … and /notation_binding/] .@
              | CoFixpoint (NonEmpty CofixBody) [NotationBinding]                              -- ^@CoFixpoint /fix_body/ with … with /fix_body/ [where /notation_binding/ and … and /notation_binding/] .@
              deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/assertion/ ::=@
data Assertion = Assertion AssertionKeyword Ident [Binder] Term                                -- ^@/assertion_keyword/ /ident/ [/binders/] : /term/ .@
               deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/assertion_keyword/ ::=@
data AssertionKeyword = Theorem                                                                -- ^@Theorem@
                      | Lemma                                                                  -- ^@Lemma@
                      | Remark                                                                 -- ^@Remark@
                      | Fact                                                                   -- ^@Fact@
                      | Corollary                                                              -- ^@Corollary@
                      | Proposition                                                            -- ^@Proposition@
                      | Definition                                                             -- ^@Definition@
                      | Example                                                                -- ^@Example@
                      deriving (Eq, Ord, Show, Read, Enum, Bounded, Typeable, Data)

-- |A \"representation\" of tactics; left as @…@ in the grammar
type Tactics = Text

-- |@/proof/ ::=@
data Proof = ProofQed      Tactics                                                             -- ^@Proof . … Qed .@
           | ProofDefined  Tactics                                                             -- ^@Proof . … Defined .@
           | ProofAdmitted Tactics                                                             -- ^@Proof . … Admitted .@
           deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/class_definition/ ::=@ /(extra)/
data ClassDefinition = ClassDefinition Ident [Binder] (Maybe Sort) [(Ident, Term)]             -- ^@Class /ident/ [/binders/] [: /sort/] := { [/ident/ : /term/ ; … ; /ident/ : /term/] } .
                     deriving (Eq, Ord, Show, Read, Typeable, Data)
                     -- TODO: field arguments (which become @forall@ed)

-- |@/instance_definition/ ::=@ /(extra)/
data InstanceDefinition = InstanceDefinition Ident [Binder] Term [(Ident, Term)] (Maybe Proof) -- ^@Instance /ident/ [/binders/] : /term/ := { [/ident/ := /term/ ; … ; /ident/ := /term/] } [/proof/] .
                        deriving (Eq, Ord, Show, Read, Typeable, Data)
                        -- TODO: field arguments (which become @fun@ arguments)

-- |@/associativity/ ::=@ /(extra)/
data Associativity = LeftAssociativity                                                         -- ^@left@
                   | RightAssociativity                                                        -- ^@right@
                   | NoAssociativity                                                           -- ^@no@
                   deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/level/ ::=@ /(extra)/
newtype Level = Level Num                                                                      -- ^@at level /num/@
              deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/notation/ ::=@ /(extra)/
data Notation = ReservedNotationIdent Ident                                                    -- ^@Reserved Notation "'/ident/'" .@
              | NotationBinding NotationBinding                                                -- ^@Notation /notation_binding/ .@
              | InfixDefinition Op Term (Maybe Associativity) Level                            -- ^@Infix "/op/" := ( /term/ ) ( [/associativity/ associativity ,] /level/ ) .@
              deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/notation_binding/ ::=@ /(extra)/
data NotationBinding = NotationIdentBinding Ident Term                                         -- ^@"'/ident/'" := (/term/) .@
                     deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/arguments/ ::=@ /(extra)/
data Arguments = Arguments (Maybe Locality) Qualid [ArgumentSpec]                              -- ^@[Local|Global]@ Arguments /qualid/ [/argument_spec/ … /argument_spec/] .@
               deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/argument_spec/ ::=@ /(extra)/
data ArgumentSpec = ArgumentSpec ArgumentExplicitness Name (Maybe Ident)                       -- ^@/name/ [% /ident/]@ or @[ /name/ ] [% /ident/]@ or @{ /name/ } [% /ident/]@
                  deriving (Eq, Ord, Show, Read, Typeable, Data)

-- |@/argument_explicitness/ ::=@ /(extra)/ – not a part of the grammar /per se/, but a common fragment
data ArgumentExplicitness = ArgExplicit                                                        -- ^@( ⋯ )@ – wrap in parentheses or nothing
                          | ArgImplicit                                                        -- ^@[ ⋯ ]@ – wrap in square brackets
                          | ArgMaximal                                                         -- ^@{ ⋯ }@ – wrap in braces
                          deriving (Eq, Ord, Show, Read, Enum, Bounded, Typeable, Data)


-- A Coq signature
data Signature = Signature { sigType   :: Term
                           , sigFixity :: Maybe (Associativity, Level) }
               deriving (Eq, Ord, Show, Read)


-- Formatting
----------------------------------------------------------------------

-- https://coq.inria.fr/refman/Reference-Manual005.html#init-notations
-- todo: make PP monadic and update this table with new declarations?
precTable :: [ (Op, (Int, Associativity)) ]
precTable =
    [ mkPrecEntry "<->" 95      NoAssociativity
    , mkPrecEntry "\\/" 85      RightAssociativity
    , mkPrecEntry "/\\" 80      RightAssociativity
    , mkPrecEntry "="   70      NoAssociativity
    , mkPrecEntry "<>"  70      NoAssociativity
    , mkPrecEntry "<"   70      NoAssociativity
    , mkPrecEntry ">"   70      NoAssociativity
    , mkPrecEntry "<="  70      NoAssociativity
    , mkPrecEntry ">="  70      NoAssociativity
    , mkPrecEntry "+"   50      LeftAssociativity
    , mkPrecEntry "||"  50      LeftAssociativity
    , mkPrecEntry "-"   50      LeftAssociativity
    , mkPrecEntry "*"   40      LeftAssociativity
    , mkPrecEntry "&&"  40      LeftAssociativity
    , mkPrecEntry "/"   40      LeftAssociativity
    , mkPrecEntry "^"   30      RightAssociativity
    ]
   where mkPrecEntry sym level assoc = (sym, (level, assoc))

-- precedence for various other expression forms
arrowPrec :: Int
arrowPrec = 20    -- right associative

appPrec   :: Int
appPrec   = 10    -- left associative

scopePrec :: Int
scopePrec = 200   -- postfix, a%scope

funPrec   :: Int
funPrec   = 200

matchPrec :: Int
matchPrec = 200

letPrec :: Int
letPrec = 200

ifPrec  :: Int
ifPrec  = 200

fixPrec :: Int
fixPrec = 200

-- precedence levels from Coq sources
-- https://github.com/coq/coq/blob/trunk/printing/ppconstr.ml
{-
latom = 0
lprod = 200
llambda = 200
lif = 200
lletin = 200
lletpattern = 200
lfix = 200
lcast = 100
larg = 9
lapp = 10
lposint = 0
lnegint = 35 -- (* must be consistent with Notation "- x" *)
ltop = 200
lproj = 1
ldelim = 1
lsimpleconstr = 8
lsimplepatt = 1
-}


maybeParen :: Bool -> Doc -> Doc
maybeParen True  = parens
maybeParen False = id

class Gallina a where
  renderGallina' :: Int -> a -> Doc

renderGallina :: Gallina a => a -> Doc
renderGallina = renderGallina' 0

renderIdent :: Ident -> Doc
renderIdent = text

renderAccessIdent :: AccessIdent -> Doc
renderAccessIdent = text . T.cons ':'

renderNum :: Num -> Doc
renderNum = integer . toInteger

renderString :: Text -> Doc
renderString = dquotes . string .: T.concatMap $ \case
                 '"' -> "\"\""
                 c   -> T.singleton c

renderOp :: Op -> Doc
renderOp = text

-- Module-local
render_type :: Term -> Doc
render_type ty = softline <> ":" <+> align (renderGallina ty)

-- Module-local
render_opt_type :: Maybe Term -> Doc
render_opt_type = maybe mempty render_type

-- Module-local
render_rtype :: Gallina a => a -> Doc
render_rtype rty = nest 2 $ softline <> renderGallina rty

-- Module-local
render_opt_rtype :: Gallina a => Maybe a -> Doc
render_opt_rtype = maybe mempty render_rtype

-- Module-local
render_in_annot :: Maybe (Qualid, [Pattern]) -> Doc
render_in_annot Nothing           = mempty
render_in_annot (Just (qid,pats)) = softline <> "in" <+> renderGallina qid
                                                     <+> render_args H pats

-- Module-local
data Orientation = H | V
                 deriving (Eq, Ord, Show, Read, Enum, Bounded, Typeable, Data)

-- Module-local
ocat :: Foldable f => Orientation -> f Doc -> Doc
ocat H = fillSep
ocat V = vsep

-- Module-local
render_args :: (Functor f, Foldable f, Gallina a) => Orientation -> f a -> Doc
render_args o = group . align . ocat o . fmap renderGallina

-- Module-local
render_args' :: (Functor f, Foldable f, Gallina a) => Int -> Orientation -> f a -> Doc
render_args' p o = group . align . ocat o . fmap (renderGallina' p)



-- Module-local
render_args_and :: (Functor f, Foldable f, Gallina a) => Orientation -> (b -> Doc) -> f a -> b -> Doc
render_args_and o f args x = render_args o args <> f x

-- Module-local
render_args_ty :: (Functor f, Foldable f, Gallina a) => Orientation -> f a -> Term -> Doc
render_args_ty o = render_args_and o $ nest 2 . render_type

-- Module-local
render_args_oty :: (Functor f, Foldable f, Gallina a) => Orientation -> f a -> Maybe Term -> Doc
render_args_oty o = render_args_and o $ nest 2 . render_opt_type

-- Module-local
render_mutual_def :: Gallina a => Doc -> NonEmpty a -> [NotationBinding] -> Doc
render_mutual_def def bodies notations =
  def <+> lineSep "with" bodies
      <>  maybe mempty (((line <> "where") <+>) . lineSep "and  ") (nonEmpty notations)
      <> "."
  where
    lineSep sep = foldr1 (\body doc -> body <!> sep <+> doc) . fmap renderGallina

-- TODO: Precedence!
instance Gallina Term where
  renderGallina' _p (Forall vars body) = parens $
    group $ "forall" <+> render_args V vars <> nest 2 ("," <!> renderGallina body)

  renderGallina' p (Fun vars body) = maybeParen (p > funPrec) $
    group $ "fun" <+> render_args V vars <+> nest 2 ("=>" <!> renderGallina' funPrec body)

  renderGallina' p (Fix fbs) = group $ maybeParen (p > fixPrec) $
    "fix" <+> renderGallina fbs

  renderGallina' _p (Cofix cbs) = group $ parens $
    "cofix" <+> renderGallina cbs

  renderGallina' p (Let var args oty val body) = group $ maybeParen (p > letPrec) $
         "let" <+> group (   renderIdent var
                         <>  spaceIf args <> render_args_oty V args oty
                         <+> nest 2 (":=" <!> renderGallina val))
               <+> "in"
    <!>  align (renderGallina body)

  renderGallina' p (LetFix def body) = group $ maybeParen (p > letPrec) $
    "let fix" <+> renderGallina def <+> "in" <!> align (renderGallina body)

  renderGallina' _p (LetCofix def body) = group $ parens $
    "let cofix" <+> renderGallina def <+> "in" <!> align (renderGallina body)

  renderGallina' _p (LetTuple vars orty val body) = group $ parens $
        "let" <+> group (   (parens . align . vsep . punctuate "," $ renderGallina <$> vars)
                        <>  render_opt_rtype orty
                        <+> nest 2 (":=" <!> renderGallina val))
    <+> "in" <!> align (renderGallina body)

  renderGallina' _p (LetTick pat val body) = group $ parens $
        "let" <+> align (group $   "'" <> align (renderGallina pat)
                               <+> nest 2 (":=" <!> renderGallina val))
    <+> "in" <!> align (renderGallina body)

  renderGallina' _p (LetTickDep pat oin val rty body) = group $ parens $
        "let" <+> align (group $   "'" <> align (renderGallina pat)
                               <>  render_in_annot oin
                               <+> nest 2 (":=" <!> renderGallina val
                                                <>  render_rtype  rty))
    <+> "in" <!> align (renderGallina body)

  renderGallina' p (If c odrty t f) = maybeParen (p > ifPrec) $
        "if"   <+> align (renderGallina c <> render_opt_rtype odrty)
    <!> "then" <+> align (renderGallina t)
    <!> "else" <+> align (renderGallina f)

  renderGallina' _p (HasType tm ty) = parens $
    renderGallina tm <+> ":" <+> renderGallina ty

  renderGallina' _p (CheckType tm ty) = parens $
    renderGallina tm <+> "<:" <+> renderGallina ty

  renderGallina' _p (ToSupportType tm) = parens $
    renderGallina tm <+> ":>"

  renderGallina' p (Arrow ty1 ty2) = maybeParen (p > arrowPrec)  $
    renderGallina' (arrowPrec + 1) ty1 <+> "->" <+> renderGallina' 200 ty2

  renderGallina' p (App f args) =  maybeParen (p > appPrec) $
    renderGallina' appPrec f </> render_args' 201 H args

  renderGallina' _p (ExplicitApp qid args) = parens $
    "@" <> renderGallina qid <> softlineIf args <> render_args H args

  renderGallina' p (Infix l op r)  =
    case lookup op precTable of
      Just (n, LeftAssociativity)  ->
        maybeParen (n < p) $
           renderGallina' n l </> renderOp op </> renderGallina' (n + 1) r
      Just (n, RightAssociativity) ->
        maybeParen (n < p) $
           renderGallina' (n + 1) l </> renderOp op </> renderGallina' n r
      Just (n, NoAssociativity)    ->
        maybeParen (n < p) $
           renderGallina' (n + 1) l </> renderOp op </> renderGallina' (n + 1) r
      Nothing                      ->
        parens $
           renderGallina l </> renderOp op </> renderGallina r

  renderGallina' p (InScope tm scope) = maybeParen (p > scopePrec) $
    renderGallina' scopePrec tm <> "%" <> renderIdent scope

  renderGallina' p (Match discriminees orty eqns) = maybeParen (p > matchPrec) $
       "match" <+> group (align . nest (-2)
                           $ (sepWith (<!>) (<+>) "," $ renderGallina <$> discriminees)
                           <> maybe mempty (\rty -> line <> renderGallina rty) orty)
               <+> "with"
    <> (case eqns of
          [] -> space
          _  -> nest 2 (line <> "| " <> sepWith (<!>) (<+>) "|" (renderGallina <$> eqns))
             <> line)
    <> "end"

  renderGallina' _ (Qualid qid) =
    renderGallina qid

  renderGallina' _ (Sort sort) =
    renderGallina sort

  renderGallina' _ (Num num) =
    renderNum num

  renderGallina' _ (PolyNum num) =
    char '#' <> renderNum num

  renderGallina' _ (String str) =
    renderString str

  renderGallina' _ (HsString str) =
    char '&' <> renderString str

  renderGallina' _ (HsChar str) =
    string "&#" <> renderString (T.singleton str)

  renderGallina' _ Underscore =
    char '_'

  renderGallina' _ (Parens t) =
    parens $ renderGallina t

  renderGallina' _ (Bang t) =
    char '!' <>  renderGallina t

  renderGallina' _ MissingValue =
    string "patternFailure"

instance Gallina Arg where
  renderGallina' p (PosArg t) =
    renderGallina' p t
  renderGallina' _ (NamedArg name t) =
    hang 2 . parens $ renderIdent name </> ":=" <+> align (renderGallina t)

-- Module-local
if_explicit :: Explicitness -> (Doc -> Doc) -> Doc -> Doc
if_explicit Explicit = ($)
if_explicit Implicit = const braces

-- Module-local
-- The 'Bool' is 'True' if parentheses are always necessary and 'False' otherwise.
binder_decoration :: Generalizability -> Explicitness -> Bool -> Doc -> Doc
binder_decoration Ungeneralizable ex b = if_explicit ex (if b then parens else id)
binder_decoration Generalizable   ex _ = ("`" <>) . if_explicit ex parens

instance Gallina Binder where
  renderGallina' _ (Inferred ex name)  =
    binder_decoration Ungeneralizable ex False $ renderGallina name
  renderGallina' _ (Typed gen ex names ty) =
    binder_decoration gen ex True $ render_args_ty H names ty
  renderGallina' _ (BindLet name oty val) =
    hang 2 . parens $ renderGallina name <> render_opt_type oty </> ":=" <+> align (renderGallina val)
  renderGallina' _ (Generalized ex ty)  =
    binder_decoration Generalizable ex True $ renderGallina ty

instance Gallina Name where
  renderGallina' _ (Ident ident)  = renderIdent ident
  renderGallina' _ UnderscoreName = char '_'

instance Gallina Qualid where
  renderGallina' _ (Bare ident)        = renderIdent ident
  renderGallina' _ (Qualified qid aid) = renderGallina qid <> renderAccessIdent aid

instance Gallina Sort where
  renderGallina' _ Prop = "Prop"
  renderGallina' _ Set  = "Set"
  renderGallina' _ Type = "Type"

instance Gallina FixBodies where
  renderGallina' p (FixOne fb) =
    renderGallina' p fb
  renderGallina' p (FixMany fb fbs var) =
    spacedSepPre "with" (align . renderGallina' p <$> fb <| fbs) </> "for" <+> renderIdent var

instance Gallina CofixBodies where
  renderGallina' p (CofixOne cb) =
    renderGallina' p cb
  renderGallina' p (CofixMany cb cbs var) =
    spacedSepPre "with" (align . renderGallina' p <$> cb <| cbs) </> "for" <+> renderIdent var

instance Gallina FixBody where
  renderGallina' _ (FixBody f args oannot oty def) =
    hang 2 $
      renderIdent f </> align (    fillSep (renderGallina <$> args)
                              </?> (renderGallina <$> oannot))
                    <>  render_opt_type oty <!> ":=" <+> align (renderGallina def)

instance Gallina CofixBody where
  renderGallina' _ (CofixBody f args oty def) =
    renderIdent f </> render_args_oty H args oty
                  </> ":=" <+> align (renderGallina def)

instance Gallina Annotation where
  renderGallina' _ (Annotation var) = braces $ "struct" <+> renderIdent var

instance Gallina MatchItem where
  renderGallina' _ (MatchItem scrutinee oas oin) =
    hang 2 $
      renderGallina scrutinee
        <> maybe mempty (\as -> softline <> "as" <+> renderGallina as) oas
        <> render_in_annot oin

instance Gallina DepRetType where
  renderGallina' _ (DepRetType oname rty) =
    maybe mempty (\name -> "as" <+> renderGallina name <> softline) oname <> renderGallina rty

instance Gallina ReturnType where
  renderGallina' _ (ReturnType ty) = "return" <+> align (renderGallina ty)

instance Gallina Equation where
  renderGallina' _ (Equation mps body) =
    spacedSepPre "|" (align . renderGallina <$> mps) <+> nest 2 ("=>" </> align (renderGallina body))

instance Gallina MultPattern where
  renderGallina' _ (MultPattern pats) = spacedSepPost "," $ renderGallina <$> pats

instance Gallina Pattern where
  renderGallina' _p (ArgsPat qid args) = parens $
    renderGallina qid </> render_args H args

  renderGallina' _p (ExplicitArgsPat qid args) = parens $
    "@" <> renderGallina qid <> softlineIf args <> render_args H args

  renderGallina' _p (InfixPat l op r) = parens $ -- TODO precedence
    renderGallina l </> renderOp op </> renderGallina r

  renderGallina' _p (AsPat pat x) = parens $
    renderGallina pat <+> "as" <+> renderIdent x

  renderGallina' _p (InScopePat pat scope) = parens $
    renderGallina pat <> "%" <> renderIdent scope

  renderGallina' _p (QualidPat qid) =
    renderGallina qid

  renderGallina' _ (UnderscorePat) =
    char '_'

  renderGallina' _ (NumPat n) =
    renderNum n

  renderGallina' _ (StringPat s) =
    renderString s

  renderGallina' _ (OrPats orPats) =
    parens . align . group $ sepWith (<>) (</>) "," (renderGallina <$> orPats)

instance Gallina OrPattern where
  renderGallina' _ (OrPattern pats) = spacedSepPre "|" (align . renderGallina <$> pats)

instance Gallina Comment where
  renderGallina' _ (Comment com) = "(* " <> align (fillSep . map (text . T.replace "*)" "* )") $ T.words com) <> " *)"

instance Gallina Sentence where
  renderGallina' p (AssumptionSentence ass)    = renderGallina' p ass
  renderGallina' p (DefinitionSentence def)    = renderGallina' p def
  renderGallina' p (InductiveSentence  ind)    = renderGallina' p ind
  renderGallina' p (FixpointSentence   fix)    = renderGallina' p fix
  renderGallina' p (AssertionSentence  ass pf) = renderGallina' p ass <!> renderGallina' p pf
  renderGallina' p (ClassSentence      cls)    = renderGallina' p cls
  renderGallina' p (InstanceSentence   ins)    = renderGallina' p ins
  renderGallina' p (NotationSentence   not)    = renderGallina' p not
  renderGallina' p (ArgumentsSentence  arg)    = renderGallina' p arg
  renderGallina' p (CommentSentence    com)    = renderGallina' p com

instance Gallina Assumption where
  renderGallina' p (Assumption kw ass) = renderGallina' p kw <+> align (renderGallina ass) <> "."

instance Gallina AssumptionKeyword where
  renderGallina' _ Axiom      = "Axiom"
  renderGallina' _ Axioms     = "Axioms"
  renderGallina' _ Conjecture = "Conjecture"
  renderGallina' _ Parameter  = "Parameter"
  renderGallina' _ Parameters = "Parameters"
  renderGallina' _ Variable   = "Variable"
  renderGallina' _ Variables  = "Variables"
  renderGallina' _ Hypothesis = "Hypothesis"
  renderGallina' _ Hypotheses = "Hypotheses"

instance Gallina Assums where
  renderGallina' _ = \case
    UnparenthesizedAssums ids ty -> renderAss ids ty
    ParenthesizedAssums   groups -> group . vsep $ parens . align . uncurry renderAss <$> groups
    where
      renderAss ids ty = fillSep (renderIdent <$> ids) <> nest 2 (render_type ty)

instance Gallina Locality where
  renderGallina' _ Global = "(*Global*)"
  renderGallina' _ Local  = "Local"

renderLocality :: Locality -> Doc
renderLocality Global = empty
renderLocality Local  = "Local" <> space

renderFullLocality :: Maybe Locality -> Doc
renderFullLocality Nothing       = empty
renderFullLocality (Just Global) = "Global" <> space
renderFullLocality (Just Local)  = "Local"  <> space

instance Gallina Definition where
  renderGallina' _ = \case
    DefinitionDef loc name args oty body -> renderDef (renderLocality loc <> "Definition") name args oty body
    LetDef            name args oty body -> renderDef "Let"                                name args oty body
    where
      renderDef def name args oty body =
        hang 2 ((def <+> renderIdent name
                     <>  spaceIf args <> render_args_oty H args oty
                     <+> ":=") <$$> renderGallina body <>  ".")

instance Gallina Inductive where
  renderGallina' _ (Inductive   bodies nots) = render_mutual_def "Inductive"   bodies nots
  renderGallina' _ (CoInductive bodies nots) = render_mutual_def "CoInductive" bodies nots

instance Gallina IndBody where
  renderGallina' _ (IndBody name params ty cons) =
    renderIdent name <> spaceIf params <> render_args_ty H params ty
                     <> nest 2 (softline <> renderCons cons)
    where
      renderCons []         = ":="
      renderCons (con:cons) = align $ foldl' (<!>) (renderCon ":=" con) (renderCon "| " <$> cons)

      renderCon delim (cname, cargs, coty) =
        delim <+> renderIdent cname <> spaceIf cargs <> render_args_oty H cargs coty

instance Gallina Fixpoint where
  renderGallina' _ (Fixpoint   bodies nots) = render_mutual_def "Fixpoint"   bodies nots
  renderGallina' _ (CoFixpoint bodies nots) = render_mutual_def "CoFixpoint" bodies nots

instance Gallina Assertion where
  renderGallina' _ (Assertion kw name args ty) =
    renderGallina kw <+> renderIdent name <> spaceIf args <> group (render_args V args)
                     <+> group (nest 2 $ ":" </> renderGallina ty)
                     <>  "."

instance Gallina AssertionKeyword where
  renderGallina' _ Theorem      = "Theorem"
  renderGallina' _ Lemma        = "Lemma"
  renderGallina' _ Remark       = "Remark"
  renderGallina' _ Fact         = "Fact"
  renderGallina' _ Corollary    = "Corollary"
  renderGallina' _ Proposition  = "Proposition"
  renderGallina' _ Definition   = "Definition"
  renderGallina' _ Example      = "Example"

instance Gallina Proof where
  renderGallina' _ = \case
    ProofQed      body -> renderProof "Qed"      body
    ProofDefined  body -> renderProof "Defined"  body
    ProofAdmitted body -> renderProof "Admitted" body
    where
      renderProof end body = "Proof." <!> indent 2 (string body) <!> end <> "."

instance Gallina ClassDefinition where
  renderGallina' _ (ClassDefinition cl params osort fields) =
    "Class" <+> renderIdent cl <> spaceIf params <> render_args_oty H params (Sort <$> osort)
            <+> nest 2 (":=" </> "{" <> lineIf fields
                                     <> sepWith (<+>) (<!>) ";" (map (\(f,ty) -> renderIdent f <+> ":" <+> renderGallina ty) fields)
                                     <> spaceIf fields <> "}.")

instance Gallina InstanceDefinition where
  renderGallina' _ (InstanceDefinition inst params cl defns mpf) =
    "Instance" <+> renderIdent inst <> spaceIf params <> render_args_ty H params (Bang cl)
               <+> nest 2 (":=" </> "{" <> lineIf defns
                                        <> sepWith (<+>) (<!>) ";" (map (\(f,def) -> renderIdent f <+> ":=" <+> renderGallina def) defns)
                                        <> spaceIf defns <> "}.")
               <>  maybe empty ((line <>) . renderGallina) mpf

instance Gallina Associativity where
  renderGallina' _ LeftAssociativity  = "left"
  renderGallina' _ RightAssociativity = "right"
  renderGallina' _ NoAssociativity    = "no"

instance Gallina Level where
  renderGallina' _ (Level n) = "at level" <+> renderNum n

instance Gallina Notation where
  renderGallina' _ (ReservedNotationIdent x) =
    "Reserved" <+> "Notation" <+> dquotes (squotes $ renderIdent x) <> "."
  renderGallina' _ (NotationBinding nb) =
    "Notation" <+> renderGallina nb <> "."
  renderGallina' _ (InfixDefinition op def oassoc level) =
    "Infix" <+> dquotes (renderOp op) <+> ":="
      </> nest 2 (parens (renderGallina def) </> parens (assoc <> renderGallina level) <> ".")
    where assoc = maybe mempty (\assoc -> renderGallina assoc <+> "associativity," <> softline) oassoc

instance Gallina NotationBinding where
  renderGallina' _ (NotationIdentBinding x def) =
    dquotes (squotes $ renderIdent x) <+> nest 2 (":=" </> parens (renderGallina def))

-- TODO: Collapse successive arguments with the same spec?
instance Gallina Arguments where
  renderGallina' _ (Arguments floc qid args) =
    renderFullLocality floc <> "Arguments" <+> renderGallina qid <> softlineIf args <> render_args H args <> "."

instance Gallina ArgumentSpec where
  renderGallina' _ (ArgumentSpec eim arg oscope) =
    let wrap = case eim of
                 ArgExplicit -> id
                 ArgImplicit -> brackets
                 ArgMaximal  -> braces
    in wrap (renderGallina arg) <> maybe mempty (("%" <>) . renderIdent) oscope

-- Make all 'Gallina' types 'Pretty' types in the default way
let abort = fail "Internal error: unexpected result from `reify'" in
  TH.reify ''Gallina >>= \case
    TH.ClassI _ is ->
      fmap concat . for is $ \case
        TH.InstanceD _ _ (TH.AppT (TH.ConT _gallina) ty) _ ->
          [d|instance Pretty $(pure ty) where pretty = renderGallina|]
        _ -> abort
    _ -> abort
