{-# LANGUAGE CPP, ExistentialQuantification #-}
#ifdef GENERICS
{-# LANGUAGE DeriveGeneric #-}
#endif

module Main (main) where

import Control.DeepSeq
import Control.Exception (evaluate)
import Criterion.Main
import qualified Data.ByteString as S
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as L

#ifdef GENERICS
import GHC.Generics
#endif

import Data.Binary
import Data.Binary.Put
import Data.ByteString.Builder as BB

main :: IO ()
main = do
  evaluate $ rnf
    [ rnf bigIntegers
    , rnf smallIntegers
    , rnf smallByteStrings
    , rnf smallStrings
    , rnf word8s
    ]
  defaultMain
    [
      bench "small Integers" $ whnf (run . fromIntegers) smallIntegers,
      bench "big Integers" $ whnf (run . fromIntegers) bigIntegers,

      bench "[small Integer]" $ whnf (run . put) smallIntegers,
      bench "[big Integer]" $ whnf (run . put) bigIntegers,

      bench "small ByteStrings" $ whnf (run . fromByteStrings) smallByteStrings,
      bench "[small ByteString]" $ whnf (run . put) smallByteStrings,

      bench "small Strings" $ whnf (run . fromStrings) smallStrings,
      bench "[small String]" $ whnf (run . put) smallStrings,

      bench "Word8s" $ whnf (run . fromWord8s) word8s,
      bench "Word8s builder" $ whnf (L.length . toLazyByteString . fromWord8sBuilder) word8s,
      bench "[Word8]" $ whnf (run . put) word8s,
      bench "Word16s" $ whnf (run . fromWord16s) word16s,
      bench "Word16s builder" $ whnf (L.length . toLazyByteString . fromWord16sBuilder) word16s,
      bench "[Word16]" $ whnf (run . put) word16s,
      bench "Word32s" $ whnf (run . fromWord32s) word32s,
      bench "Word32s builder" $ whnf (L.length . toLazyByteString . fromWord32sBuilder) word32s,
      bench "[Word32]" $ whnf (run . put) word32s,
      bench "Word64s" $ whnf (run . fromWord64s) word64s,
      bench "Word64s builder" $ whnf (L.length . toLazyByteString . fromWord64sBuilder) word64s,
      bench "[Word64]" $ whnf (run . put) word64s

#ifdef GENERICS
      , bgroup "Generics" [
        bench "Struct monoid put" $ whnf (run . fromStructs) structs,
        bench "Struct put as list" $ whnf (run . put) structs,
        bench "StructList monoid put" $ whnf (run . fromStructLists) structLists,
        bench "StructList put as list" $ whnf (run . put) structLists
      ]
#endif
    ]
  where
    run = L.length . runPut

#ifdef GENERICS
data Struct = Struct Word8 Word16 Word32 Word64 deriving Generic
instance Binary Struct

data StructList = StructList [Struct] deriving Generic
instance Binary StructList

structs :: [Struct]
structs = take 10000 $ [ Struct a b 0 0 | a <- [0 .. maxBound], b <- [0 .. maxBound] ]

structLists :: [StructList]
structLists = replicate 1000 (StructList (take 10 structs))
#endif

-- Input data

smallIntegers :: [Integer]
smallIntegers = [0..10000]
{-# NOINLINE smallIntegers #-}

bigIntegers :: [Integer]
bigIntegers = [max .. max + 10000]
  where
    max :: Integer
    max = fromIntegral (maxBound :: Word64)
{-# NOINLINE bigIntegers #-}

smallByteStrings :: [S.ByteString]
smallByteStrings = replicate 10000 $ C.pack "abcdefghi"
{-# NOINLINE smallByteStrings #-}

smallStrings :: [String]
smallStrings = replicate 10000 "abcdefghi"
{-# NOINLINE smallStrings #-}

word8s :: [Word8]
word8s = take 10000 $ cycle [minBound .. maxBound]
{-# NOINLINE word8s #-}

word16s :: [Word16]
word16s = take 10000 $ cycle [minBound .. maxBound]
{-# NOINLINE word16s #-}

word32s :: [Word32]
word32s = take 10000 $ cycle [minBound .. maxBound]
{-# NOINLINE word32s #-}

word64s :: [Word64]
word64s = take 10000 $ cycle [minBound .. maxBound]
{-# NOINLINE word64s #-}

------------------------------------------------------------------------
-- Benchmarks

fromIntegers :: [Integer] -> Put
fromIntegers [] = return ()
fromIntegers (x:xs) = put x >> fromIntegers xs

fromByteStrings :: [S.ByteString] -> Put
fromByteStrings [] = return ()
fromByteStrings (x:xs) = put x >> fromByteStrings xs

fromStrings :: [String] -> Put
fromStrings [] = return ()
fromStrings (x:xs) = put x >> fromStrings xs

fromWord8s :: [Word8] -> Put
fromWord8s [] = return ()
fromWord8s (x:xs) = put x >> fromWord8s xs

fromWord8sBuilder :: [Word8] -> BB.Builder
fromWord8sBuilder [] = mempty
fromWord8sBuilder (x:xs) = BB.word8 x `mappend` fromWord8sBuilder xs

fromWord16s :: [Word16] -> Put
fromWord16s [] = return ()
fromWord16s (x:xs) = put x >> fromWord16s xs

fromWord16sBuilder :: [Word16] -> BB.Builder
fromWord16sBuilder [] = mempty
fromWord16sBuilder (x:xs) = BB.word16BE x `mappend` fromWord16sBuilder xs

fromWord32s :: [Word32] -> Put
fromWord32s [] = return ()
fromWord32s (x:xs) = put x >> fromWord32s xs

fromWord32sBuilder :: [Word32] -> BB.Builder
fromWord32sBuilder [] = mempty
fromWord32sBuilder (x:xs) = BB.word32BE x `mappend` fromWord32sBuilder xs

fromWord64s :: [Word64] -> Put
fromWord64s [] = return ()
fromWord64s (x:xs) = put x >> fromWord64s xs

fromWord64sBuilder :: [Word64] -> BB.Builder
fromWord64sBuilder [] = mempty
fromWord64sBuilder (x:xs) = BB.word64BE x `mappend` fromWord64sBuilder xs

#ifdef GENERICS
fromStructs :: [Struct] -> Put
fromStructs [] = return ()
fromStructs (x:xs) = put x >> fromStructs xs

fromStructLists :: [StructList] -> Put
fromStructLists [] = return ()
fromStructLists (x:xs) = put x >> fromStructLists xs
#endif
