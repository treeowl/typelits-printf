{-# LANGUAGE KindSignatures       #-}
{-# LANGUAGE NoStarIsType         #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeInType           #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module GHC.TypeLits.Printf.Internal.Parser where

import           Data.Kind
import           GHC.TypeLits

-- hello, we're going to attempt to implement
-- https://docs.microsoft.com/en-us/cpp/c-runtime-library/format-specification-syntax-printf-and-wprintf-functions?view=vs-2019

-- | A type synonym for a single-character symbol
type SChar = Symbol

type Parser a = a -> Type

type family RunParser (p :: Parser a) (str :: [SChar]) :: Maybe (a, [SChar])

data Pure :: a -> Parser a
type instance RunParser (Pure x) str = 'Just '(x, str)

data Sym :: SChar -> Parser SChar
type family SymHelp (c :: SChar) (str :: [SChar]) :: Maybe (SChar, [SChar]) where
    SymHelp c (c ': cs) = 'Just '(c, cs)
    SymHelp c d         = 'Nothing
type instance RunParser (Sym c) cs = SymHelp c cs

data NotSym :: SChar -> Parser SChar
type family NotSymHelp (c :: SChar) (str :: [SChar]) :: Maybe (SChar, [SChar]) where
    NotSymHelp c (c ': cs) = 'Nothing
    NotSymHelp c (d ': cs) = 'Just '(d, cs)
    NotSymHelp c '[]       = 'Nothing
type instance RunParser (NotSym c) cs = NotSymHelp c cs

data AnySym :: Parser SChar
type family AnySymHelp (str :: [SChar]) :: Maybe (SChar, [SChar]) where
    AnySymHelp (c ': cs) = 'Just '(c, cs)
    AnySymHelp '[]       = 'Nothing
type instance RunParser AnySym cs = AnySymHelp cs

data (<$) :: b -> Parser a -> Parser b
type family RepHelp (x :: b) (r :: Maybe (a, [SChar])) :: Maybe (b, [SChar]) where
    RepHelp x 'Nothing        = 'Nothing
    RepHelp x ('Just '(y, s)) = 'Just '(x, s)
type instance RunParser (x <$ p) str = RepHelp x (RunParser p str)

data (<|>) :: Parser a -> Parser a -> Parser a
type family ChoiceMaybe (x :: Maybe a) (y :: Maybe a) :: Maybe a where
    ChoiceMaybe ('Just x) y = 'Just x
    ChoiceMaybe 'Nothing  y = y
type instance RunParser (x <|> y) str = ChoiceMaybe (RunParser x str) (RunParser y str)

type Optional p = ('Just <$> p) <|> Pure 'Nothing

data (*>) :: Parser a -> Parser b -> Parser b
type family SeqHelp (p :: Parser b) (r :: Maybe (a, [SChar])) :: Maybe (b, [SChar]) where
    SeqHelp p 'Nothing          = 'Nothing
    SeqHelp p ('Just '(x, str)) = RunParser p str
type instance RunParser (x *> y) str = SeqHelp y (RunParser x str)

-- | Parse a single digit
data Digit :: Parser Nat 
type family DigitHelp (d :: Maybe Nat) (cs :: [SChar]) :: Maybe (Nat, [SChar]) where
    DigitHelp 'Nothing  cs = 'Nothing
    DigitHelp ('Just d) cs = 'Just '(d, cs)
type instance RunParser Digit '[]       = 'Nothing
type instance RunParser Digit (c ': cs) = DigitHelp (CharDigit c) cs

data (<$>) :: (a -> b) -> Parser a -> Parser b
type family MapConHelp (f :: a -> b) (r :: Maybe (a, [SChar])) :: Maybe (b, [SChar]) where
    MapConHelp f 'Nothing = 'Nothing
    MapConHelp f ('Just '(x, str)) = 'Just '(f x, str)
type instance RunParser (f <$> p) str = MapConHelp f (RunParser p str)

data (<*>) :: Parser (a -> b) -> Parser a -> Parser b
type family ApHelp (r :: Maybe (a -> b, [SChar])) (q :: Parser a) :: Maybe (b, [SChar]) where
    ApHelp 'Nothing q          = 'Nothing
    ApHelp ('Just '(f, str)) q = RunParser (f <$> q) str
type instance RunParser (p <*> q) str = ApHelp (RunParser p str) q

data Many :: Parser a -> Parser [a]
type instance RunParser (Many p) str = RunParser (Some p <|> Pure '[]) str
data Some :: Parser a -> Parser [a]
type instance RunParser (Some p) str = RunParser ('(:) <$> p <*> Many p) str

-- | Parse a number
data Number :: Parser Nat
type family NumberHelp (xs :: Maybe ([Nat], [SChar])) :: Maybe (Nat, [SChar]) where
    NumberHelp 'Nothing           = 'Nothing
    NumberHelp ('Just '(ns, str)) = 'Just '(FromDigits ns 0, str)
type instance RunParser Number str = NumberHelp (RunParser (Many Digit) str)

data Cat :: Parser [SChar] -> Parser Symbol
type family CatHelp (xs :: Maybe ([SChar], [SChar])) :: Maybe (Symbol, [SChar]) where
    CatHelp 'Nothing           = 'Nothing
    CatHelp ('Just '(cs, str)) = 'Just '(CatChars cs, str)
type instance RunParser (Cat p) str = CatHelp (RunParser p str)

type family EvalHelp (r :: Maybe (a, [SChar])) :: Maybe a where
    EvalHelp 'Nothing          = 'Nothing
    EvalHelp ('Just '(x, str)) = 'Just x
type EvalParser (p :: Parser a) str = EvalHelp (RunParser p str) :: Maybe a

type family EvalHelp_ (r :: Maybe (a, [SChar])) :: a where
    EvalHelp_ ('Just '(x, str)) = x
type EvalParser_ (p :: Parser a) str = EvalHelp_ (RunParser p str) :: a

type family CharDigit (c :: SChar) :: Maybe Nat where
    CharDigit "0" = 'Just 0
    CharDigit "1" = 'Just 1
    CharDigit "2" = 'Just 2
    CharDigit "3" = 'Just 3
    CharDigit "4" = 'Just 4
    CharDigit "5" = 'Just 5
    CharDigit "6" = 'Just 6
    CharDigit "7" = 'Just 7
    CharDigit "8" = 'Just 8
    CharDigit "9" = 'Just 9
    CharDigit c   = 'Nothing

type family FromDigits (xs :: [Nat]) (n :: Nat) :: Nat where
    FromDigits '[]       n = n
    FromDigits (a ': bs) n = FromDigits bs (n * 10 + a)

type family CatChars (cs :: [SChar]) :: Symbol where
    CatChars '[]       = ""
    CatChars (c ': cs) = AppendSymbol c (CatChars cs)
