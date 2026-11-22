import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.Locale

import scala.collection.mutable
import scala.util.Try
import scala.util.control.NonFatal

object Main {

  private case class ScoreEntry(points: Long, order: Long)

  // Общая таблица лидеров.
  private class Leaderboard {
    private val results = mutable.Map.empty[String, ScoreEntry]
    private var sequence = 0L

    // Добавление или обновление лучшего результата.
    def submit(player: String, points: Long): String = synchronized {
      results.get(player) match {
        case None =>
          sequence += 1
          results(player) = ScoreEntry(points, sequence)
          s"OK: результат игрока $player установлен: $points"

        case Some(old) if points > old.points =>
          sequence += 1
          results(player) = ScoreEntry(points, sequence)
          s"OK: лучший результат игрока $player обновлён: $points"

        case Some(old) =>
          s"OK: лучший результат игрока $player не изменён: ${old.points}"
      }
    }

    // Сортировка: очки по убыванию, время получения по возрастанию.
    private def sortedEntries: Vector[(String, ScoreEntry)] = {
      results.toVector.sortWith { (a, b) =>
        if (a._2.points == b._2.points) {
          a._2.order < b._2.order
        } else {
          a._2.points > b._2.points
        }
      }
    }

    // Получение TOP n.
    def top(n: Int): String = synchronized {
      val entries = sortedEntries.take(n)

      if (entries.isEmpty) {
        "Таблица лидеров пуста"
      } else {
        entries.zipWithIndex.map {
          case ((player, entry), index) =>
            s"${index + 1}. $player — ${entry.points}"
        }.mkString(" | ")
      }
    }

    // Получение места игрока.
    def rank(player: String): Option[(Int, Long)] = synchronized {
      sortedEntries.zipWithIndex.collectFirst {
        case ((name, entry), index) if name == player =>
          (index + 1, entry.points)
      }
    }

    // Удаление игрока из таблицы.
    def reset(player: String): Boolean = synchronized {
      results.remove(player).isDefined
    }
  }

  // Обработка одной команды клиента.
  private def processCommand(
      line: String,
      board: Leaderboard
  ): (String, Boolean) = {

    val trimmed = line.trim

    if (trimmed.isEmpty) {
      return ("ОШИБКА: пустая команда", true)
    }

    val parts = trimmed.split("\\s+").toList
    val command = parts.head.toUpperCase(Locale.ROOT)
    val args = parts.tail

    command match {

      case "SUBMIT" =>
        args match {
          case player :: pointsText :: Nil =>
            Try(pointsText.toLong).toOption match {
              case Some(points) =>
                (board.submit(player, points), true)

              case None =>
                ("ОШИБКА: очки должны быть целым числом", true)
            }

          case _ =>
            ("ОШИБКА: используйте SUBMIT игрок очки", true)
        }

      case "TOP" =>
        args match {
          case nText :: Nil =>
            Try(nText.toInt).toOption match {
              case Some(n) if n > 0 =>
                (board.top(n), true)

              case Some(_) =>
                ("ОШИБКА: количество мест должно быть больше нуля", true)

              case None =>
                ("ОШИБКА: n должно быть целым числом", true)
            }

          case _ =>
            ("ОШИБКА: используйте TOP n", true)
        }

      case "RANK" =>
        args match {
          case player :: Nil =>
            board.rank(player) match {
              case Some((place, points)) =>
                (s"$player: место $place, очки $points", true)

              case None =>
                (s"ОШИБКА: неизвестный игрок $player", true)
            }

          case _ =>
            ("ОШИБКА: используйте RANK игрок", true)
        }

      case "RESET" =>
        args match {
          case player :: Nil =>
            if (board.reset(player)) {
              (s"OK: игрок $player удалён из таблицы", true)
            } else {
              (s"ОШИБКА: неизвестный игрок $player", true)
            }

          case _ =>
            ("ОШИБКА: используйте RESET игрок", true)
        }

      case "QUIT" =>
        if (args.isEmpty) {
          ("BYE: соединение закрыто", false)
        } else {
          ("ОШИБКА: используйте QUIT без аргументов", true)
        }

      case _ =>
        (
          "ОШИБКА: неизвестная команда. Доступны: SUBMIT, TOP, RANK, RESET, QUIT",
          true
        )
    }
  }

  // Обработка отдельного TCP-подключения.
  private def handleClient(socket: Socket, board: Leaderboard): Unit = {
    try {
      val reader = new BufferedReader(
        new InputStreamReader(
          socket.getInputStream,
          StandardCharsets.UTF_8
        )
      )

      val writer = new PrintWriter(
        new OutputStreamWriter(
          socket.getOutputStream,
          StandardCharsets.UTF_8
        ),
        true
      )

      var connected = true
      var line = reader.readLine()

      while (connected && line != null) {
        val (response, keepConnection) =
          processCommand(line, board)

        writer.println(response)

        connected = keepConnection

        if (connected) {
          line = reader.readLine()
        }
      }

    } catch {
      case _: java.net.SocketException =>
        ()

      case NonFatal(e) =>
        System.err.println(
          s"Ошибка обработки клиента: ${e.getMessage}"
        )

    } finally {
      try {
        socket.close()
      } catch {
        case NonFatal(_) => ()
      }
    }
  }

  // Запуск TCP-сервера.
  private def startServer(port: Int): Unit = {
    val board = new Leaderboard()

    try {
      val serverSocket = new ServerSocket(port)

      println(s"TCP-сервер таблицы лидеров запущен на порту $port")

      try {
        while (true) {
          val socket = serverSocket.accept()

          println(
            s"Новое подключение: ${socket.getRemoteSocketAddress}"
          )

          // Для каждого клиента создаётся отдельный поток.
          val clientThread = new Thread(
            new Runnable {
              override def run(): Unit = {
                handleClient(socket, board)
              }
            },
            s"client-${socket.getPort}"
          )

          clientThread.start()
        }
      } finally {
        serverSocket.close()
      }

    } catch {
      case e: java.net.BindException =>
        System.err.println(
          s"ОШИБКА: порт $port уже используется"
        )

      case NonFatal(e) =>
        System.err.println(
          s"Ошибка сервера: ${e.getMessage}"
        )
    }
  }

  def main(args: Array[String]): Unit = {
    if (args.length > 1) {
      System.err.println("Использование: scala main.scala [port]")
      return
    }

    val parsedPort =
      if (args.isEmpty) Some(5000)
      else Try(args(0).toInt).toOption

    parsedPort match {
      case Some(port) if port >= 1 && port <= 65535 =>
        startServer(port)

      case Some(_) =>
        System.err.println(
          "ОШИБКА: номер порта должен быть от 1 до 65535"
        )

      case None =>
        System.err.println(
          "ОШИБКА: номер порта должен быть целым числом"
        )
    }
  }
}