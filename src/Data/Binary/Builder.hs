-----------------------------------------------------------------------------
-- |
-- Module      : Data.Binary.Builder
-- Copyright   : Ross Paterson
-- License     : BSD3-style (see LICENSE)
-- 
-- Maintainer  : Lennart Kolmodin <kolmodin@dtek.chalmers.se>
-- Stability   : experimental
-- Portability : portable to Hugs and GHC
--
-- Efficient construction of lazy bytestrings.
--
-----------------------------------------------------------------------------

module Data.Binary.Builder (

    -- * The Builder type
      Builder
    , runBuilder

    -- * Constructing Builders
    , empty
    , singleton
    , append
    , fromByteString        -- :: S.ByteString -> Builder
    , fromLazyByteString    -- :: L.ByteString -> Builder

    -- * Flushing the buffer state
    , flush

    -- * Derived Builders
    -- ** Big-endian writes
    , putWord16be           -- :: Word16 -> Builder
    , putWord32be           -- :: Word32 -> Builder
    , putWord64be           -- :: Word64 -> Builder

    -- ** Little-endian writes
    , putWord16le           -- :: Word16 -> Builder
    , putWord32le           -- :: Word32 -> Builder
    , putWord64le           -- :: Word64 -> Builder

  ) where

import Foreign
import Data.Monoid
import Data.Word
import Data.ByteString.Base (inlinePerformIO)
import qualified Data.ByteString.Base as S
import qualified Data.ByteString.Lazy as L

------------------------------------------------------------------------

-- | A 'Builder' is an efficient way to build lazy 'L.ByteString's.
-- There are several functions for constructing 'Builder's, but only one
-- to inspect them: to extract any data, you have to turn them into lazy
-- 'L.ByteString's using 'runBuilder'.
--
-- Internally, a 'Builder' constructs a lazy 'L.Bytestring' by filling byte
-- arrays piece by piece.  As each buffer is filled, it is \'popped\'
-- off, to become a new chunk of the resulting lazy 'L.ByteString'.
-- All this is hidden from the user of the 'Builder'.

newtype Builder = Builder {
        unBuilder :: (Buffer -> [S.ByteString]) -> Buffer -> [S.ByteString]
    }

instance Monoid Builder where
    mempty = empty
    mappend = append

------------------------------------------------------------------------

-- | /O(1)./ The empty Builder, satisfying
--
--  * @'runBuilder' 'empty' = 'L.empty'@
--
empty :: Builder
empty = Builder id

-- | /O(1)./ A Builder taking a single byte, satisfying
--
--  * @'runBuilder' ('singleton' b) = 'L.singleton' b@
--
singleton :: Word8 -> Builder
singleton = writeN 1 . flip poke

-- | /O(1)./ The concatenation of two Builders, satisfying
--
--  * @'runBuilder' ('append' x y) = 'L.append' ('runBuilder' x) ('runBuilder' y)@
--
append :: Builder -> Builder -> Builder
append (Builder f) (Builder g) = Builder (f . g)

-- | /O(1)./ A Builder taking a 'S.ByteString', satisfying
--
--  * @'runBuilder' ('fromByteString' bs) = 'L.fromChunks' [bs]@
--
fromByteString :: S.ByteString -> Builder
fromByteString bs = flush `append` mapBuilder (bs :)

-- | /O(1)./ A Builder taking a lazy 'L.ByteString', satisfying
--
--  * @'runBuilder' ('fromLazyByteString' bs) = bs@
--
fromLazyByteString :: L.ByteString -> Builder
fromLazyByteString (S.LPS bss) = flush `append` mapBuilder (bss ++)

------------------------------------------------------------------------

-- Our internal buffer type
data Buffer = Buffer {-# UNPACK #-} !(ForeignPtr Word8)
                     {-# UNPACK #-} !Int                -- offset
                     {-# UNPACK #-} !Int                -- used bytes
                     {-# UNPACK #-} !Int                -- length left

------------------------------------------------------------------------

-- | /O(n)./ Extract a lazy 'L.ByteString' from a 'Builder'.
-- The construction work takes place if and when the relevant part of
-- the lazy 'L.ByteString' is demanded.
--
runBuilder :: Builder -> L.ByteString
runBuilder m = S.LPS $ inlinePerformIO $ do
    buf <- newBuffer defaultSize
    return (unBuilder (m `append` flush) (const []) buf)

-- | /O(1)./ Pop the 'S.ByteString' we have constructed so far, if any,
-- yielding a new chunk in the result lazy 'L.ByteString'.
flush :: Builder
flush = Builder $ \ k buf@(Buffer p o u l) ->
    if u == 0
      then k buf
      else S.PS p o u : k (Buffer p (o+u) 0 l)

------------------------------------------------------------------------

--
-- copied from Data.ByteString.Lazy
--
defaultSize :: Int
defaultSize = 32 * k - overhead
    where k = 1024
          overhead = 2 * sizeOf (undefined :: Int)

------------------------------------------------------------------------

-- | Sequence an IO operation on the buffer
unsafeLiftIO :: (Buffer -> IO Buffer) -> Builder
unsafeLiftIO f =  Builder $ \ k buf -> inlinePerformIO $ do
    buf' <- f buf
    return (k buf')
{-# INLINE unsafeLiftIO #-}

-- | Get the size of the buffer
withSize :: (Int -> Builder) -> Builder
withSize f = Builder $ \ k buf@(Buffer _ _ _ l) ->
    unBuilder (f l) k buf

-- | Map the resulting list of bytestrings.
mapBuilder :: ([S.ByteString] -> [S.ByteString]) -> Builder
mapBuilder f = Builder (f .)

------------------------------------------------------------------------

-- | Ensure that there are at least @n@ many bytes available.
ensureFree :: Int -> Builder
ensureFree n = n `seq` withSize $ \ l ->
    if n <= l then empty else
        flush `append` unsafeLiftIO (const (newBuffer (max n defaultSize)))
{-# INLINE [1] ensureFree #-}

-- | Ensure that @n@ many bytes are available, and then use @f@ to write some
-- bytes into the memory.
writeN :: Int -> (Ptr Word8 -> IO ()) -> Builder
writeN n f = ensureFree n `append` unsafeLiftIO (writeNBuffer n f)
{-# INLINE [1] writeN #-}

writeNBuffer :: Int -> (Ptr Word8 -> IO ()) -> Buffer -> IO Buffer
writeNBuffer n f (Buffer fp o u l) = do
    withForeignPtr fp (\p -> f (p `plusPtr` (o+u)))
    return (Buffer fp o (u+n) (l-n))

newBuffer :: Int -> IO Buffer
newBuffer size = do
    fp <- S.mallocByteString size
    return $! Buffer fp 0 0 size

------------------------------------------------------------------------

--
-- We rely on the fromIntegral to do the right masking for us.
--

-- | Write a Word16 in big endian format
putWord16be :: Word16 -> Builder
putWord16be w16 =
    let w1 = shiftR w16 8
        w2 = w16
    in
    singleton (fromIntegral w1) `append`
    singleton (fromIntegral w2)
{-# INLINE putWord16be #-}

-- | Write a Word16 in little endian format
putWord16le :: Word16 -> Builder
-- putWord16le w16 = writeN 2 (\p -> poke (castPtr p) w16)

putWord16le w16 =
    let w2 = shiftR w16 8
        w1 = w16
    in
    singleton (fromIntegral w1) `append`
    singleton (fromIntegral w2)
{-# INLINE putWord16le #-}

-- | Write a Word32 in big endian format
putWord32be :: Word32 -> Builder
putWord32be w32 =
    let w1 = w32 `shiftR` 24
        w2 = w32 `shiftR` 16
        w3 = w32 `shiftR`  8
        w4 = w32
    in
    singleton (fromIntegral w1) `append`
    singleton (fromIntegral w2) `append`
    singleton (fromIntegral w3) `append`
    singleton (fromIntegral w4)
{-# INLINE putWord32be #-}

-- | Write a Word32 in little endian format
putWord32le :: Word32 -> Builder
putWord32le w32 =
    let w4 = w32 `shiftR` 24
        w3 = w32 `shiftR` 16
        w2 = w32 `shiftR`  8
        w1 = w32
    in
    singleton (fromIntegral w1) `append`
    singleton (fromIntegral w2) `append`
    singleton (fromIntegral w3) `append`
    singleton (fromIntegral w4)
{-# INLINE putWord32le #-}

-- on a little endian machine:
-- putWord32le w32 = writeN 4 (\p -> poke (castPtr p) w32)

-- | Write a Word64 in big endian format
putWord64be :: Word64 -> Builder
putWord64be w64 =
    let w1 = w64 `shiftR` 56
        w2 = w64 `shiftR` 48
        w3 = w64 `shiftR` 40
        w4 = w64 `shiftR` 32
        w5 = w64 `shiftR` 24
        w6 = w64 `shiftR` 16
        w7 = w64 `shiftR`  8
        w8 = w64
    in
    singleton (fromIntegral w1) `append`
    singleton (fromIntegral w2) `append`
    singleton (fromIntegral w3) `append`
    singleton (fromIntegral w4) `append`
    singleton (fromIntegral w5) `append`
    singleton (fromIntegral w6) `append`
    singleton (fromIntegral w7) `append`
    singleton (fromIntegral w8)
{-# INLINE putWord64be #-}

-- | Write a Word64 in little endian format
putWord64le :: Word64 -> Builder
putWord64le w64 =
    let w1 = w64 `shiftR` 56
        w2 = w64 `shiftR` 48
        w3 = w64 `shiftR` 40
        w4 = w64 `shiftR` 32
        w5 = w64 `shiftR` 24
        w6 = w64 `shiftR` 16
        w7 = w64 `shiftR`  8
        w8 = w64
    in
    singleton (fromIntegral w8) `append`
    singleton (fromIntegral w7) `append`
    singleton (fromIntegral w6) `append`
    singleton (fromIntegral w5) `append`
    singleton (fromIntegral w4) `append`
    singleton (fromIntegral w3) `append`
    singleton (fromIntegral w2) `append`
    singleton (fromIntegral w1)
{-# INLINE putWord64le #-}

-- on a little endian machine:
-- putWord64le w64 = writeN 8 (\p -> poke (castPtr p) w64)