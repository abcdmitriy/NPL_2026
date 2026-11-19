
with Ada.Text_IO;
with Ada.Integer_Text_IO;
with Ada.Command_Line;
with Ada.Real_Time;

procedure Main is

   use Ada.Text_IO;
   use Ada.Real_Time;

   type Sum_Array is array (Positive range <>) of Long_Long_Integer;

   type Matrix is array (Positive range <>, Positive range <>) of Integer;
   type Matrix_Access is access all Matrix;

   N, M : Positive;
   A : Matrix_Access;

   Input_File : File_Type;

   procedure Run(Worker_Count : Positive) is

      protected type Result_Store(
         Rows : Positive;
         Cols : Positive;
         Workers : Positive
      ) is
         procedure Add_Row(
            Row_Index : Positive;
            Row_Value : Long_Long_Integer
         );

         procedure Add_Columns(Partial_Columns : Sum_Array);
         procedure Worker_Done;

         entry Wait_Complete;

         function Get_Row_Sum(Index : Positive)
            return Long_Long_Integer;

         function Get_Column_Sum(Index : Positive)
            return Long_Long_Integer;

         function Get_Max_Sum return Long_Long_Integer;
         function Get_Max_Row return Positive;

      private
         Row_Totals : Sum_Array(1 .. Rows) := (others => 0);
         Column_Totals : Sum_Array(1 .. Cols) := (others => 0);

         Max_Sum : Long_Long_Integer := Long_Long_Integer'First;
         Max_Row : Positive := 1;

         Finished : Natural := 0;
      end Result_Store;

      protected body Result_Store is

         procedure Add_Row(
            Row_Index : Positive;
            Row_Value : Long_Long_Integer
         ) is
         begin
            Row_Totals(Row_Index) := Row_Value;

            if Row_Value > Max_Sum then
               Max_Sum := Row_Value;
               Max_Row := Row_Index;
            end if;
         end Add_Row;

         procedure Add_Columns(Partial_Columns : Sum_Array) is
         begin
            for J in 1 .. Cols loop
               Column_Totals(J) :=
                  Column_Totals(J) + Partial_Columns(J);
            end loop;
         end Add_Columns;

         procedure Worker_Done is
         begin
            Finished := Finished + 1;
         end Worker_Done;

         entry Wait_Complete when Finished = Workers is
         begin
            null;
         end Wait_Complete;

         function Get_Row_Sum(Index : Positive)
            return Long_Long_Integer is
         begin
            return Row_Totals(Index);
         end Get_Row_Sum;

         function Get_Column_Sum(Index : Positive)
            return Long_Long_Integer is
         begin
            return Column_Totals(Index);
         end Get_Column_Sum;

         function Get_Max_Sum return Long_Long_Integer is
         begin
            return Max_Sum;
         end Get_Max_Sum;

         function Get_Max_Row return Positive is
         begin
            return Max_Row;
         end Get_Max_Row;

      end Result_Store;

      Store : Result_Store(N, M, Worker_Count);

      task type Worker(First_Row, Last_Row : Positive);

      task body Worker is
         Row_Sum : Long_Long_Integer;
         Partial_Columns : Sum_Array(1 .. M) := (others => 0);
      begin
         for I in First_Row .. Last_Row loop

            Row_Sum := 0;

            for J in 1 .. M loop
               Row_Sum := Row_Sum + Long_Long_Integer(A(I, J));

               Partial_Columns(J) :=
                  Partial_Columns(J) + Long_Long_Integer(A(I, J));
            end loop;

            Store.Add_Row(I, Row_Sum);

         end loop;

         Store.Add_Columns(Partial_Columns);
         Store.Worker_Done;
      end Worker;

      type Worker_Access is access Worker;

      type Worker_Array is
         array (Positive range <>) of Worker_Access;

      Workers : Worker_Array(1 .. Worker_Count);

      Start_Time, End_Time : Time;
      Elapsed : Duration;

      Total_Rows : Long_Long_Integer := 0;
      Total_Columns : Long_Long_Integer := 0;

      First_Row, Last_Row : Positive;

   begin
      Start_Time := Clock;

      -- Создание параллельных задач
      for K in 1 .. Worker_Count loop

         First_Row := ((K - 1) * N) / Worker_Count + 1;
         Last_Row := (K * N) / Worker_Count;

         Workers(K) := new Worker(First_Row, Last_Row);

      end loop;

      -- Ожидание завершения всех задач
      Store.Wait_Complete;

      End_Time := Clock;
      Elapsed := To_Duration(End_Time - Start_Time);

      Put_Line("====================================");
      Put_Line("Количество задач:" & Positive'Image(Worker_Count));
      Put_Line("====================================");

      Put_Line("Суммы строк:");

      for I in 1 .. N loop
         Put_Line(
            "Строка" & Positive'Image(I) & ": " &
            Long_Long_Integer'Image(Store.Get_Row_Sum(I))
         );

         Total_Rows := Total_Rows + Store.Get_Row_Sum(I);
      end loop;

      New_Line;
      Put_Line("Суммы столбцов:");

      for J in 1 .. M loop
         Put_Line(
            "Столбец" & Positive'Image(J) & ": " &
            Long_Long_Integer'Image(Store.Get_Column_Sum(J))
         );

         Total_Columns :=
            Total_Columns + Store.Get_Column_Sum(J);
      end loop;

      New_Line;

      Put_Line(
         "Максимальная сумма строки: " &
         Long_Long_Integer'Image(Store.Get_Max_Sum)
      );

      Put_Line(
         "Номер строки: " &
         Positive'Image(Store.Get_Max_Row)
      );

      New_Line;

      Put_Line(
         "Сумма всех строк: " &
         Long_Long_Integer'Image(Total_Rows)
      );

      Put_Line(
         "Сумма всех столбцов: " &
         Long_Long_Integer'Image(Total_Columns)
      );

      if Total_Rows = Total_Columns then
         Put_Line("Проверка: успешно");
      else
         Put_Line("Проверка: ошибка");
      end if;

      Put_Line(
         "Время выполнения: " & Duration'Image(Elapsed) & " секунд"
      );

      New_Line;

   end Run;

begin

   -- Открытие входного файла
   if Ada.Command_Line.Argument_Count >= 1 then
      Open(Input_File, In_File, Ada.Command_Line.Argument(1));
   else
      Open(Input_File, In_File, "input.txt");
   end if;

   -- Чтение размеров матрицы
   Ada.Integer_Text_IO.Get(Input_File, N);
   Ada.Integer_Text_IO.Get(Input_File, M);

   A := new Matrix(1 .. N, 1 .. M);

   -- Чтение элементов матрицы
   for I in 1 .. N loop
      for J in 1 .. M loop
         Ada.Integer_Text_IO.Get(Input_File, A(I, J));
      end loop;
   end loop;

   Close(Input_File);

   Put_Line(
      "Размер матрицы:" & Positive'Image(N) &
      " x" & Positive'Image(M)
   );

   New_Line;

   -- Последовательное выполнение одной задачей
   Run(1);

   -- Параллельное выполнение N задачами
   Run(N);

end Main;
