#!/usr/bin/env runidris

module Main

import Data.List
import Data.Nat
import System
import System.Console.GetOpt
import Data.String
import Data.Maybe
import Data.Fin
import System.File

-- rainbow

Color : Type
Color = (Nat, Nat, Nat)

red : Color
red = (255, 0, 0)

orange : Color
orange = (255, 165, 0)

yellow : Color
yellow = (255, 255, 0)

green : Color
green = (0, 255, 0)

blue : Color
blue = (0, 0, 255)

indigo : Color
indigo = (75, 0, 130)

violet : Color
violet = (238, 130, 238)

keyColors : List Color
keyColors = [red, orange, yellow, green, blue, indigo, violet]

rainbow'' : Nat -> Color -> Color -> List Color -> List Color
rainbow'' 1 _ _ sofar = sofar
rainbow'' wi (rx, gx, bx) (ry, gy, by) sofar =
    rainbow'' (wi `minus` 1) newcolor (ry, gy, by) (sofar ++ [newcolor])
  where
    combine : Nat -> Nat -> Nat
    combine a b with (a > b)
        combine a b | True  = a `minus` ((a `minus` b) `div` wi)
        combine a b | False = a `plus` ((b `minus` a) `div` wi)
    newcolor : Color
    newcolor = (combine rx ry, combine gx gy, combine bx by)

rainbow' : Nat -> List Color -> List Color -> List Color
rainbow' _ [ ] sofar = sofar
rainbow' _ [_] sofar = sofar
-- rainbow' _ [c] [] = [c]
-- rainbow' _ [c] (sf::sfs) = init (sf::sfs) ++ [c]
rainbow' wi (cx::cy::cs) sofar =
    rainbow' (wi `minus` chunk) (cy::cs) (sofar ++ rainbow'' chunk cx cy [cx])
  where
    chunk : Nat
    chunk = wi `div` ((length (cx::cy::cs)) `minus` 1)

rainbow : Nat -> List Color
rainbow width with (width <= length keyColors)
    rainbow width | True  = take width keyColors
    rainbow width | False = rainbow' width keyColors []

-- colorize

data Layer = Foreground | Background 
data ColorFormat = RGB
data Escape = Start | End | ClearFormatting 

layerCode : Layer -> String
layerCode Foreground = "38;"
layerCode Background = "48;"

cformatCode : ColorFormat -> String
cformatCode RGB = "2;"

escapeCode : Escape -> String
escapeCode Start = "\x1b["
escapeCode End = "m"
escapeCode ClearFormatting = "0"

colorize : Layer -> String -> Color -> String
colorize lc message (cr,cg,cb) =
      escapeCode Start ++ layerCode lc ++ cformatCode RGB
   ++ show cr ++ ";" ++ show cg ++ ";" ++ show cb 
   ++ escapeCode End
   ++ message
   ++ escapeCode Start ++ escapeCode ClearFormatting ++ escapeCode End

-- |Generate some text that's colored like a rainbow.
interface Rainbowize a where
    rainbowize : a -> String

-- |Color an input string like a rainbow.
Rainbowize String where
    rainbowize txt = 
        concat
      $ zipWith (colorize Foreground) (map cast $ unpack txt) (rainbow (length txt))

-- |Generate a rainbow colored block N characters wide.
Rainbowize Nat where
    rainbowize le =
        concat
      $ map (colorize Background " ") (rainbow le)

-- |Generate a rainbow colored block N characters wide.
Rainbowize Integer where
    rainbowize le =
        concat
      $ map (colorize Background " ") (rainbow $ cast le)

record Options where
    constructor MkOptions
    optShowHelp  : Bool
    optWidth     : Maybe Integer

defaults : Options
defaults = MkOptions False Nothing

opts : List (OptDescr (Options -> Options))
opts =
    [ MkOpt ['h']     ["help"]
        -- (NoArg (\os => { optShowHelp := True } os))
        (NoArg (\os =>  MkOptions True os.optWidth))
        "show this help text"
    , MkOpt ['w']     ["width"]
        (OptArg ((\w,os => 
            MkOptions os.optShowHelp (parseInteger (fromMaybe "" w))))
            "number")
        "width of rainbow to print"
    ]

-- |Get the width of the current terminal in columns. BTW using 'stty size'
-- instead of 'tput cols' because 'tput' reports the wrong size under certain
-- cirmustances
terminalWidth : IO (Maybe Integer)
terminalWidth = do
    (output, _) <- run "stty size | awk '{print $2}'"
    pure $ parseInteger output

finalOpts : List String -> Options
finalOpts args = 
    foldl (flip id) defaults (results args).options
  where
    results : List String -> Result (Options -> Options)
    results args = getOpt Permute opts args

helpHeader : String
helpHeader = "rainbow - print all the colors of the " 
          ++ rainbowize "rainbow" ++ "\n\n"
          ++ "Usage: rainbow [OPTIONS] [STRING]\n\n"
          ++ "Available options:"

clearRainbow : Maybe Integer -> Maybe Integer -> String
clearRainbow (Just ow) _ = rainbowize ow
clearRainbow _ (Just tw) = rainbowize tw
clearRainbow Nothing Nothing = rainbowize 80

getPipedMessage : IO (Either FileError String)
getPipedMessage = do
    si <- openFile "/dev/stdin" Read
    case si of
        Left e => pure $ Left e
        Right f => do
            size <- fileSize f
            case size of
                Left e => pure $ Left e
                Right s => do
                    message <- fGetChars f s
                    case message of
                        Left e => pure $ Left e
                        Right m => pure $ Right m

main : IO ()
main = do
    args <- getArgs
    pipedMessage <- getPipedMessage
    let o = finalOpts args
    case o.optShowHelp of
        True => putStr $ usageInfo helpHeader opts
        False => case pipedMessage of
            Right m => putStr $ rainbowize m
            Left _ => do
                tw <- terminalWidth
                putStr $ case nonOptions $ getOpt Permute opts args of
                    [ ] => clearRainbow o.optWidth tw
                    [_] => clearRainbow o.optWidth tw
                    (x::xs) => (rainbowize (unwords xs)) ++ "\n"
