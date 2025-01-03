#!/usr/bin/env cabal
{- cabal:
build-depends:
    base
  , rio
  , optparse-applicative
  , prettyprinter
-}

-- Copyright (c) 2021 Scott Bonds <scott@ggr.com>
-- ISC License, see https://en.wikipedia.org/wiki/ISC_license

{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE BinaryLiterals #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DoAndIfThenElse #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE ViewPatterns #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -Wcompat #-}
{-# OPTIONS_GHC -Widentities #-}
{-# OPTIONS_GHC -Wincomplete-record-updates #-}
{-# OPTIONS_GHC -Wincomplete-uni-patterns #-}
{-# OPTIONS_GHC -Wpartial-fields #-}
{-# OPTIONS_GHC -Wredundant-constraints #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Unused LANGUAGE pragma" #-}

module Main where

import RIO
import RIO.ByteString as B
import RIO.List as L
import RIO.Process as P
import RIO.Text as T
import Options.Applicative as O
import System.Environment as E
import Prettyprinter (pretty)

main :: IO ()
main = do
    args <- withProgName "rainbow" $ execParser opts
    wi <- width' (width args)

    -- need to wait for a little bit, or the piped stdin might not be ready
    -- otherwise we could have used: gotPipedMessage <- RIO.hReady stdin
    gotPipedMessage <- hWaitForInput stdin 100
    
    mmsg' <- if gotPipedMessage then do
                 Just . decodeUtf8Lenient <$> B.getContents
             else 
                 return $ message args
    B.putStr $ encodeUtf8 $ colorit wi mmsg' <> "\n"
  where
    colorit :: Int -> Maybe Text -> Text
    colorit wid mmess =
        case mmess of
            Just mess -> rainbowize mess
            Nothing   -> rainbowize wid

data Options = Options
  { width :: Maybe Int
  , message :: Maybe Text
  }

options :: Parser Options
options = Options
      <$> optional (option auto
          ( long "width"
         <> short 'w'
         <> metavar "WIDTH"
         <> help "number of characters to print, defaults to the width of the terminal" ))
      <*> optional (argument str
          ( help "string to rainbowize"
         <> metavar "STRING" ))

opts :: ParserInfo Options
opts = info (options <**> helper)
  ( fullDesc
  <> headerDoc (Just $ pretty $ "rainbow - print all the colors of the "
     <> rainbowize ("rainbow" :: Text))
  <> progDesc "" )

-- |Get the width of the current terminal in columns 
-- or failing that, assume its 80 columns wide.
-- BTW using 'stty size' instead of 'tput cols' because 'tput' reports
-- the wrong size under certain cirmustances
width' :: Maybe Int -> IO Int
width' widthParam = do
    (cols, _) <- readProcess_ "stty size | awk '{print $2}'"
    let widthFromTerminal = fromMaybe 80 (readMaybe $ T.unpack $ decodeUtf8Lenient $ B.toStrict cols :: Maybe Int)
    return $ fromMaybe widthFromTerminal widthParam

class Rainbowize a where
    -- |Generate some text that's colored like a rainbow.
    rainbowize :: a -> Text

instance Rainbowize Int where
    -- |Generate a rainbow colored block N characters wide.
    rainbowize le =
        T.concat
      $ L.map (colorize Background " ") (rainbow le)

instance Rainbowize Text where
    -- |Color an input string like a rainbow.
    rainbowize txt = 
        T.concat
      $ L.zipWith (colorize Foreground) (chunksOf 1 txt) (rainbow le)
      where
        le = T.length txt

colorize :: Layer -> Text -> Color -> Text
colorize lc message (cr,cg,cb) =
      escapeCode Start <> layerCode lc <> cformatCode RGB
   <> T.pack (show cr) <> ";" <> T.pack (show cg) <> ";" <> T.pack (show cb) 
   <> escapeCode End
   <> message
   <> escapeCode Start <> escapeCode ClearFormatting <> escapeCode End

data Layer = Foreground | Background 

layerCode :: Layer -> Text
layerCode Foreground = "38;"
layerCode Background = "48;"

data ColorFormat = RGB

cformatCode :: ColorFormat -> Text
cformatCode RGB = "2;"

data Escape = Start | End | ClearFormatting 

escapeCode :: Escape -> Text
escapeCode Start = "\x1b["
escapeCode End = "m"
escapeCode ClearFormatting = "0"

red :: Color
red = (255, 0, 0)

orange :: Color
orange = (255, 165, 0)

yellow :: Color
yellow = (255, 255, 0)

green :: Color
green = (0, 255, 0)

cyan :: Color
cyan = (0, 255, 255)

blue :: Color
blue = (0, 0, 255)

indigo :: Color
indigo = (75, 0, 130)

violet :: Color
violet = (238, 130, 238)

type Color = (Int, Int, Int)

keyColors :: [Color]
keyColors = [red, orange, yellow, green, cyan, blue, indigo, violet]

rainbow :: Int -> [Color]
rainbow width
    | width <= L.length keyColors = L.take width keyColors
    | otherwise = rainbow' width keyColors []

rainbow' :: Int -> [Color] -> [Color] -> [Color]
rainbow' _ [ ] sofar = sofar
rainbow' _ [_] sofar = sofar
rainbow' wi colors@(cx:cy:cs) sofar =
    rainbow' (wi - chunk) (cy:cs) (sofar ++ rainbow'' chunk cx cy [cx])
  where
    chunk = wi `div` ((L.length colors)-1)

rainbow'' :: Int -> Color -> Color -> [Color] -> [Color]
rainbow'' wi (rx, gx, bx) cy@(ry, gy, by) sofar
    | wi == 1 = sofar
    | otherwise = rainbow'' (wi-1) newcolor cy (sofar ++ [newcolor])
  where
    newcolor = ((rx + (ry-rx) `div` wi)
              , (gx + (gy-gx) `div` wi)
              , (bx + (by-bx) `div` wi))
