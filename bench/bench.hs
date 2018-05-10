{-# LANGUAGE BangPatterns #-}

module Main where

import Criterion.Main
import Data.Int
import Data.Word
import Data.Scientific

import           Control.Monad                (mplus)
import           Data.Char                    (intToDigit, ord)
import qualified Text.Read                       as Read
import           Text.Read                        (readPrec)
import qualified Text.ParserCombinators.ReadPrec as ReadPrec
import           Text.ParserCombinators.ReadPrec  ( ReadPrec )
import qualified Text.ParserCombinators.ReadP    as ReadP
import           Text.ParserCombinators.ReadP     ( ReadP )

main :: IO ()
main = defaultMain
       [ bgroup "realToFrac"
         [ bgroup "Scientific->Double"
           [ sToD "dangerouslyBig"   dangerouslyBig
           , sToD "dangerouslySmall" dangerouslySmall
           , sToD "pos"              pos
           , sToD "neg"              neg
           , sToD "int"              int
           , sToD "negInt"           negInt
           ]
         , bgroup "Double->Scientific"
           [ dToS "pos"    pos
           , dToS "neg"    neg
           , dToS "int"    int
           , dToS "negInt" negInt
           ]
         ]
       , bgroup "floor"
         [ bench "floor"        (nf (floor :: Scientific -> Integer) $! pos)
         , bench "floorDefault" (nf floorDefault                     $! pos)
         ]
       , bgroup "ceiling"
         [ bench "ceiling"        (nf (ceiling :: Scientific -> Integer) $! pos)
         , bench "ceilingDefault" (nf ceilingDefault                     $! pos)
         ]
       , bgroup "truncate"
         [ bench "truncate"        (nf (truncate :: Scientific -> Integer) $! pos)
         , bench "truncateDefault" (nf truncateDefault                     $! pos)
         ]

       , bgroup "round"
         [ bench "round"        (nf (round :: Scientific -> Integer) $! pos)
         , bench "roundDefault" (nf roundDefault                     $! pos)
         ]

       , bgroup "toDecimalDigits"
         [ bench "big" (nf toDecimalDigits $! big)
         ]

       , bgroup "fromFloatDigits"
         [ bench "pos"    $ nf (fromFloatDigits :: Double -> Scientific) pos
         , bench "neg"    $ nf (fromFloatDigits :: Double -> Scientific) neg
         , bench "int"    $ nf (fromFloatDigits :: Double -> Scientific) int
         , bench "negInt" $ nf (fromFloatDigits :: Double -> Scientific) negInt
         ]

       , bgroup "toBoundedInteger"
         [ bgroup "0"              $ benchToBoundedInteger 0
         , bgroup "dangerouslyBig" $ benchToBoundedInteger dangerouslyBig
         , bgroup "64"             $ benchToBoundedInteger 64
         ]

       , bgroup "read"
         [ benchRead "123456789.123456789"
         , benchRead "12345678900000000000.12345678900000000000000000"
         , benchRead "12345678900000000000.12345678900000000000000000e1234"
         ]
       ]
    where
      pos :: Fractional a => a
      pos = 12345.12345

      neg :: Fractional a => a
      neg = -pos

      int :: Fractional a => a
      int = 12345

      negInt :: Fractional a => a
      negInt = -int

      big :: Scientific
      big = read $ "0." ++ concat (replicate 20 "0123456789")

      dangerouslyBig :: Scientific
      dangerouslyBig = read "1e500"

      dangerouslySmall :: Scientific
      dangerouslySmall = read "1e-500"

benchRead :: String -> Benchmark
benchRead s =
    bgroup s
    [ bench "new" $ nf (ReadPrec.readPrec_to_S (readPrec :: ReadPrec Scientific) 0) s
    , bench "old" $ nf (ReadPrec.readPrec_to_S oldReadPrecScientific 0) s
    ]

realToFracStoD :: Scientific -> Double
realToFracStoD = fromRational . toRational
{-# INLINE realToFracStoD #-}

realToFracDtoS :: Double -> Scientific
realToFracDtoS = fromRational . toRational
{-# INLINE realToFracDtoS #-}

sToD :: String -> Scientific -> Benchmark
sToD name f = bgroup name
              [ bench "toRealFloat"  . nf (realToFrac     :: Scientific -> Double) $! f
              , bench "via Rational" . nf (realToFracStoD :: Scientific -> Double) $! f
              ]

dToS :: String -> Double -> Benchmark
dToS name f = bgroup name
              [ bench "fromRealFloat"  . nf (realToFrac     :: Double -> Scientific) $! f
              , bench "via Rational"   . nf (realToFracDtoS :: Double -> Scientific) $! f
              ]

floorDefault :: Scientific -> Integer
floorDefault x = if r < 0 then n - 1 else n
                 where (n,r) = properFraction x
{-# INLINE floorDefault #-}

ceilingDefault :: Scientific -> Integer
ceilingDefault x = if r > 0 then n + 1 else n
                   where (n,r) = properFraction x
{-# INLINE ceilingDefault #-}

truncateDefault :: Scientific -> Integer
truncateDefault x =  m where (m,_) = properFraction x
{-# INLINE truncateDefault #-}

roundDefault :: Scientific -> Integer
roundDefault x = let (n,r) = properFraction x
                     m     = if r < 0 then n - 1 else n + 1
                 in case signum (abs r - 0.5) of
                      -1 -> n
                      0  -> if even n then n else m
                      1  -> m
                      _  -> error "round default defn: Bad value"
{-# INLINE roundDefault #-}

benchToBoundedInteger :: Scientific -> [Benchmark]
benchToBoundedInteger s =
    [ bench "Int"    $ nf (toBoundedInteger :: Scientific -> Maybe Int)    s
    , bench "Int8"   $ nf (toBoundedInteger :: Scientific -> Maybe Int8)   s
    , bench "Int16"  $ nf (toBoundedInteger :: Scientific -> Maybe Int16)  s
    , bench "Int32"  $ nf (toBoundedInteger :: Scientific -> Maybe Int32)  s
    , bench "Int64"  $ nf (toBoundedInteger :: Scientific -> Maybe Int64)  s
    , bench "Word"   $ nf (toBoundedInteger :: Scientific -> Maybe Word)   s
    , bench "Word8"  $ nf (toBoundedInteger :: Scientific -> Maybe Word8)  s
    , bench "Word16" $ nf (toBoundedInteger :: Scientific -> Maybe Word16) s
    , bench "Word32" $ nf (toBoundedInteger :: Scientific -> Maybe Word32) s
    , bench "Word64" $ nf (toBoundedInteger :: Scientific -> Maybe Word64) s
    ]

oldReadPrecScientific :: ReadPrec Scientific
oldReadPrecScientific = Read.parens $ ReadPrec.lift (ReadP.skipSpaces >> oldScientificP)

-- A strict pair
data SP = SP !Integer {-# UNPACK #-}!Int

oldScientificP :: ReadP Scientific
oldScientificP = do
  let positive = (('+' ==) <$> ReadP.satisfy isSign) `mplus` return True
  pos <- positive

  let step :: Num a => a -> Int -> a
      step a digit = a * 10 + fromIntegral digit
      {-# INLINE step #-}

  n <- foldDigits step 0

  let s = SP n 0
      fractional = foldDigits (\(SP a e) digit ->
                                 SP (step a digit) (e-1)) s

  SP coeff expnt <- (ReadP.satisfy (== '.') >> fractional)
                    ReadP.<++ return s

  let signedCoeff | pos       =   coeff
                  | otherwise = (-coeff)

      eP = do posE <- positive
              e <- foldDigits step 0
              if posE
                then return   e
                else return (-e)

  (ReadP.satisfy isE >>
           ((scientific signedCoeff . (expnt +)) <$> eP)) `mplus`
     return (scientific signedCoeff    expnt)

foldDigits :: (a -> Int -> a) -> a -> ReadP a
foldDigits f z = do
    c <- ReadP.satisfy isDecimal
    let digit = ord c - 48
        a = f z digit

    ReadP.look >>= go a
  where
    go !a [] = return a
    go !a (c:cs)
        | isDecimal c = do
            _ <- ReadP.get
            let digit = ord c - 48
            go (f a digit) cs
        | otherwise = return a

isDecimal :: Char -> Bool
isDecimal c = c >= '0' && c <= '9'
{-# INLINE isDecimal #-}

isSign :: Char -> Bool
isSign c = c == '-' || c == '+'
{-# INLINE isSign #-}

isE :: Char -> Bool
isE c = c == 'e' || c == 'E'
{-# INLINE isE #-}
