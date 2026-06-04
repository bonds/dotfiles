#!/usr/bin/env runidris

module Main

import Data.List
import Data.Maybe
import Data.Nat
import Data.String
import System
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

cyan : Color
cyan = (0, 255, 255)

blue : Color
blue = (0, 0, 255)

indigo : Color
indigo = (75, 0, 130)

violet : Color
violet = (238, 130, 238)

keyColors : List Color
keyColors = [red, orange, yellow, green, cyan, blue, indigo, violet]

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
    optMessage   : Maybe String

defaults : Options
defaults = MkOptions False Nothing Nothing

parseArgs : List String -> Options
parseArgs args = go args defaults
  where
    go : List String -> Options -> Options
    go [] opts = opts
    go (x :: rest) opts = case x of
        "--help" => go rest (MkOptions True opts.optWidth opts.optMessage)
        "-h" => go rest (MkOptions True opts.optWidth opts.optMessage)
        "--width" => case rest of
            (w :: rest') => go rest' (MkOptions opts.optShowHelp (parseInteger w) opts.optMessage)
            [] => opts
        "-w" => case rest of
            (w :: rest') => go rest' (MkOptions opts.optShowHelp (parseInteger w) opts.optMessage)
            [] => opts
        _ => case opts.optMessage of
                Nothing => go rest (MkOptions opts.optShowHelp opts.optWidth (Just x))
                Just m  => go rest (MkOptions opts.optShowHelp opts.optWidth (Just (m ++ " " ++ x)))

-- |Get the width of the current terminal in columns. BTW using 'stty size'
-- instead of 'tput cols' because 'tput' reports the wrong size under certain
-- cirmustances
terminalWidth : IO (Maybe Integer)
terminalWidth = do
    (output, _) <- run "stty size | awk '{print $2}'"
    pure $ parseInteger output

helpText : String
helpText = "rainbow - print all the colors of the " 
        ++ rainbowize "rainbow" ++ "\n\n"
        ++ "Usage: rainbow [-w|--width WIDTH] [STRING]\n\n"
        ++ "Available options:\n"
        ++ "  -w,--width WIDTH         number of characters to print, defaults to the\n"
        ++ "                           width of the terminal\n"
        ++ "  STRING                   string to rainbowize\n"
        ++ "  -h,--help                Show this help text\n"

clearRainbow : Maybe Integer -> Maybe Integer -> String
clearRainbow (Just ow) _ = rainbowize ow
clearRainbow _ (Just tw) = rainbowize tw
clearRainbow Nothing Nothing = rainbowize 80

readAllLines : File -> IO (Either FileError String)
readAllLines f = go ""
  where
    go : String -> IO (Either FileError String)
    go acc = do
        Right line <- fGetLine f
            | Left _ => pure (Right acc)
        let acc' = acc ++ line
        if line == ""
            then pure (Right acc')
            else go acc'

getPipedMessage : IO (Maybe String)
getPipedMessage = do
    (isTerm, _) <- run "test -t 0 && echo yes || echo no"
    case trim isTerm of
        "yes" => pure Nothing
        _ => do
            Right f <- openFile "/dev/stdin" Read
                | Left _ => pure Nothing
            Right contents <- readAllLines f
                | Left _ => pure Nothing
            closeFile f
            let trimmed = trim contents
            case trimmed of
                "" => pure Nothing
                _  => pure (Just trimmed)

main : IO ()
main = do
    allArgs <- getArgs
    let o = parseArgs (drop 1 allArgs)
    if o.optShowHelp
        then putStr helpText
        else do
            piped <- getPipedMessage
            case piped of
                Just m  => putStrLn $ rainbowize m
                Nothing => case o.optMessage of
                    Just m  => putStrLn $ rainbowize m
                    Nothing => do
                        tw <- terminalWidth
                        putStr $ clearRainbow o.optWidth tw
