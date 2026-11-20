use std::collections::{HashMap, HashSet};
use std::fs;
use std::sync::mpsc;
use std::thread;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

struct Lcg(u64);

impl Lcg {
    fn next(&mut self) -> u64 {
        self.0 = self.0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);

        self.0 >> 33
    }
}

fn is_palindrome(chars: &[char]) -> bool {
    if chars.is_empty() {
        return false;
    }

    let mut left = 0;
    let mut right = chars.len() - 1;

    while left < right {
        if chars[left] != chars[right] {
            return false;
        }

        left += 1;
        right -= 1;
    }

    true
}

fn find_sequential(chars: &[char], len: usize) -> Vec<usize> {
    let mut result = Vec::new();

    if len == 0 || chars.len() < len {
        return result;
    }

    for i in 0..=(chars.len() - len) {
        if is_palindrome(&chars[i..i + len]) {
            result.push(i);
        }
    }

    result
}

fn find_parallel(chars: &[char], len: usize, threads: usize) -> Vec<usize> {
    let n = chars.len();

    if len == 0 || n < len || threads == 0 {
        return Vec::new();
    }

    let total_positions = n - len + 1;
    let worker_count = threads.min(total_positions);

    let (tx, rx) = mpsc::channel();
    let mut handles = Vec::new();

    let base = total_positions / worker_count;
    let remainder = total_positions % worker_count;

    let mut next_start = 0;

    for t in 0..worker_count {
        let count = base + usize::from(t < remainder);

        let start = next_start;
        let end_start = start + count;

        next_start = end_start;

        let slice_end = end_start + len - 1;
        let part: Vec<char> = chars[start..slice_end].to_vec();

        let tx = tx.clone();

        handles.push(thread::spawn(move || {
            let mut local = Vec::new();

            for i in 0..count {
                if is_palindrome(&part[i..i + len]) {
                    local.push(start + i);
                }
            }

            tx.send(local).expect("Ошибка отправки результатов");
        }));
    }

    drop(tx);

    let mut set: HashSet<usize> = HashSet::new();

    for positions in rx {
        set.extend(positions);
    }

    for handle in handles {
        handle.join().expect("Ошибка рабочего потока");
    }

    let mut result: Vec<usize> = set.into_iter().collect();
    result.sort_unstable();

    result
}

fn most_frequent(
    chars: &[char],
    positions: &[usize],
    len: usize,
) -> Option<(String, usize)> {
    if len == 0 {
        return None;
    }

    let mut map: HashMap<String, usize> = HashMap::new();

    for &position in positions {
        let palindrome: String = chars[position..position + len]
            .iter()
            .collect();

        *map.entry(palindrome).or_insert(0) += 1;
    }

    map.into_iter().max_by(|(s1, c1), (s2, c2)| {
        c1.cmp(c2).then_with(|| s2.cmp(s1))
    })
}

fn generate_text(size: usize) -> String {
    let seed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as u64;

    let mut rng = Lcg(seed);

    let alphabet = ['a', 'b', 'c', 'd'];
    let palindrome = ['a', 'b', 'a', 'c', 'a', 'b', 'a'];

    let mut out = String::with_capacity(size);

    for position in 0..size {
        if position % 500 < palindrome.len() {
            out.push(palindrome[position % 500]);
        } else {
            let index = (rng.next() % 4) as usize;
            out.push(alphabet[index]);
        }
    }

    out
}

fn run_experiment(text: &str, name: &str, len: usize) {
    let chars: Vec<char> = text.chars().collect();

    println!("\n========================================");
    println!("Тест: {}", name);
    println!("Длина текста: {}", chars.len());
    println!("Длина палиндрома L = {}", len);
    println!("========================================\n");

    let t0 = Instant::now();
    let seq = find_sequential(&chars, len);
    let seq_time = t0.elapsed();

    println!(" потоков |   время   | ускорение | совпадение");
    println!("---------+-----------+-----------+-----------");

    for threads in [1, 2, 4, 8] {
        let t0 = Instant::now();

        let par = find_parallel(&chars, len, threads);

        let par_time = t0.elapsed();

        let same = if par == seq { "OK" } else { "FAIL" };

        let speedup = if par_time.as_nanos() > 0 {
            seq_time.as_secs_f64() / par_time.as_secs_f64()
        } else {
            0.0
        };

        println!(
            " {:7} | {:>9.3?} | {:>8.2}x | {}",
            threads,
            par_time,
            speedup,
            same
        );
    }

    let par = find_parallel(&chars, len, 4);

    println!("\nВсего палиндромов длины {}: {}", len, par.len());

    if par.is_empty() {
        println!("Палиндромы не найдены.");
    } else {
        println!("Первые 10 позиций:");

        for &position in par.iter().take(10) {
            let palindrome: String = chars[position..position + len]
                .iter()
                .collect();

            println!("  позиция {:7}: {}", position, palindrome);
        }

        if let Some((palindrome, count)) = most_frequent(&chars, &par, len) {
            println!(
                "\nСамая частая палиндромная подстрока: \"{}\" (встречается {} раз)",
                palindrome,
                count
            );
        }
    }

    println!("\nПоследовательное время: {:.3?}", seq_time);
}

fn main() {
    println!("=== Задача 1.3: параллельный поиск палиндромных подстрок (Rust) ===");

    let len = 7;

    match fs::read_to_string("input.txt") {
        Ok(content) => {
            let clean: String = content
                .chars()
                .filter(|c| *c != '\n' && *c != '\r')
                .collect();

            println!("Файл input.txt успешно прочитан.");

            run_experiment(&clean, "Текст из input.txt", len);
        }

        Err(error) => {
            println!("Не удалось прочитать input.txt: {}", error);
            println!("Первый эксперимент пропущен.");
        }
    }

    let generated = generate_text(1_000_000);

    println!("Сгенерировано 1 000 000 символов.");
    println!("Алфавит: a, b, c, d.");

    run_experiment(&generated, "Случайно сгенерированный текст", len);

    println!("\n=== Все эксперименты завершены ===");
}