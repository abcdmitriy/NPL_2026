
module Main where

import Data.List (find)
import Data.Array
import Control.Exception (catch, IOException)

data Cell = Empty | Blocked | Domino Char deriving (Eq, Show)

readInput :: FilePath -> IO (Int, Int, [(Int, Int)])
readInput path = do
    content <- readFile path
    let ws = words content

    if length ws < 2
        then error "Недостаточно данных во входном файле"
        else do
            let n = read (head ws) :: Int
                m = read (ws !! 1) :: Int
                coords = map read (drop 2 ws) :: [Int]

            if n <= 0 || m <= 0
                then error "Размеры доски должны быть положительными"
                else if odd (length coords)
                    then error "Некорректный список координат"
                    else return (n, m, pairs coords)
  where
    pairs (a:b:rest) = (a, b) : pairs rest
    pairs _ = []

createBoard :: Int -> Int -> [(Int, Int)] -> Array (Int, Int) Cell
createBoard n m blocked = array ((1, 1), (n, m))
    [ ((i, j), if (i, j) `elem` blocked then Blocked else Empty)
    | i <- [1..n], j <- [1..m] ]

findFirstEmpty :: Array (Int, Int) Cell -> Maybe (Int, Int)
findFirstEmpty board = find (\pos -> board ! pos == Empty)
    [ (i, j) | i <- [1..n], j <- [1..m] ]
  where
    ((1, 1), (n, m)) = bounds board

generateTilings :: Array (Int, Int) Cell -> Char -> [Array (Int, Int) Cell]
generateTilings board ch =
    case findFirstEmpty board of
        Nothing -> [board]
        Just (i, j) ->
            let next = succ ch
                ((1, 1), (n, m)) = bounds board

                horz
                    | j + 1 <= m && board ! (i, j + 1) == Empty =
                        let b2 = board // [((i, j), Domino ch), ((i, j + 1), Domino ch)]
                        in generateTilings b2 next
                    | otherwise = []

                vert
                    | i + 1 <= n && board ! (i + 1, j) == Empty =
                        let b2 = board // [((i, j), Domino ch), ((i + 1, j), Domino ch)]
                        in generateTilings b2 next
                    | otherwise = []

            in horz ++ vert

formatBoard :: Array (Int, Int) Cell -> String
formatBoard board = unlines
    [ [ cellChar (board ! (i, j)) | j <- [1..m] ] | i <- [1..n] ]
  where
    ((1, 1), (n, m)) = bounds board

    cellChar Empty      = '.'
    cellChar Blocked    = '#'
    cellChar (Domino c) = c

main :: IO ()
main = do
    putStrLn "=== Задача 2.1: Рекурсивная генерация замощений доски (Haskell) ===\n"

    result <- catch
        (do
            (n, m, blocked) <- readInput "input.txt"

            if any (\(i, j) -> i < 1 || i > n || j < 1 || j > m) blocked
                then error "Координаты запрещённых клеток выходят за границы доски"
                else do
                    let board = createBoard n m blocked
                        free = length
                            [ () | i <- [1..n], j <- [1..m],
                                   board ! (i, j) == Empty ]

                    putStrLn $ "Размер доски: " ++ show n ++ " x " ++ show m
                    putStrLn $ "Запрещённых клеток: " ++ show (n * m - free)

                    if odd free
                        then putStrLn "\nЗамощений нет: нечётное число свободных клеток"
                        else do
                            let tilings = generateTilings board 'A'
                                count = length tilings

                            putStrLn $ "\nВсего замощений: " ++ show count

                            if count > 0
                                then do
                                    putStrLn "\nПервое найденное замощение:"
                                    putStr $ formatBoard (head tilings)
                                else
                                    putStrLn "\nЗамощений не найдено"
        )
        (\e -> putStrLn $ "Ошибка: " ++ show (e :: IOException))

    return ()
