#!/usr/bin/env runidris

module Main

import Data.List
import Data.Nat
import System
import Data.String
import Data.Maybe
import Data.Fin

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
rainbow' _ [c] [] = [c]
rainbow' _ [c] (sf::sfs) = init (sf::sfs) ++ [c]
rainbow' wi (cx::cy::cs) sofar =
    rainbow' (wi `minus` chunk) (cy::cs) (sofar ++ rainbow'' chunk cx cy [cx])
  where
    chunk : Nat
    chunk = wi `div` ((length (cx::cy::cs)) `minus` 1)

rainbow : Nat -> List Color
rainbow width = rainbow' width keyColors []

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

help : String
help = "truecolor - print all the colors of the " 
    ++  rainbowize "rainbow" ++ "\n\n"
    ++ "Usage: truecolor [-w|--width WIDTH] [STRING]\n\n"
    ++ "Available options:\n"
    ++ "  -w,--width WIDTH         number of characters to print, defaults to the width\n"
    ++ "                           of the terminal\n"
    ++ "  STRING                   string to rainbowize\n"
    ++ "  -h,--help                Show this help text\n"

-- |Get the width of the current terminal in columns or, failing that, assume
-- its 80 columns wide. BTW using 'stty size' instead of 'tput cols' because
-- 'tput' reports the wrong size under certain cirmustances
width : IO Integer
width = do
    (output, _) <- run "stty size | awk '{print $2}'"
    pure $ fromMaybe 80 $ parseInteger output

main : IO ()
main = do
    w <- width
    args <- getArgs
    putStrLn help
    putStrLn $ rainbowize w
