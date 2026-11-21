using Sockets

# ─── Лексер ────────────────────────────────────────────────────────────────
struct Token
    kind::Symbol   # :num, :ident, :op, :lparen, :rparen, :eof
    text::String
end

function tokenize(s::AbstractString)
    chars = collect(s)
    tokens = Token[]
    i = 1
    n = length(chars)

    while i <= n
        c = chars[i]

        if isspace(c)
            i += 1
        elseif c in ('+', '-', '*', '/')
            push!(tokens, Token(:op, string(c)))
            i += 1
        elseif c == '('
            push!(tokens, Token(:lparen, "("))
            i += 1
        elseif c == ')'
            push!(tokens, Token(:rparen, ")"))
            i += 1
        elseif isdigit(c) || c == '.'
            start = i
            digits_before_dot = 0
            digits_after_dot = 0

            while i <= n && isdigit(chars[i])
                digits_before_dot += 1
                i += 1
            end

            if i <= n && chars[i] == '.'
                i += 1

                while i <= n && isdigit(chars[i])
                    digits_after_dot += 1
                    i += 1
                end
            end

            if digits_before_dot + digits_after_dot == 0
                error("Invalid number: $(String(chars[start:min(i, n)]))")
            end

            # Необязательная научная запись: 1e3, 2.5e-4.
            if i <= n && (chars[i] == 'e' || chars[i] == 'E')
                i += 1

                if i <= n && (chars[i] == '+' || chars[i] == '-')
                    i += 1
                end

                exponent_digits = 0

                while i <= n && isdigit(chars[i])
                    exponent_digits += 1
                    i += 1
                end

                if exponent_digits == 0
                    error("Invalid exponent in number: $(String(chars[start:min(i - 1, n)]))")
                end
            end

            number_text = String(chars[start:i-1])
            parsed = tryparse(Float64, number_text)
            parsed === nothing && error("Invalid number: $number_text")

            push!(tokens, Token(:num, number_text))

        elseif isletter(c) || c == '_'
            start = i

            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '_')
                i += 1
            end

            push!(tokens, Token(:ident, String(chars[start:i-1])))

        else
            error("Unexpected character: '$c'")
        end
    end

    push!(tokens, Token(:eof, ""))
    return tokens
end

# ─── Парсер: рекурсивный спуск ──────────────────────────────────────────────
mutable struct Parser
    tokens::Vector{Token}
    pos::Int
    vars::Dict{String, Float64}
end

peek(p::Parser) = p.tokens[p.pos]

function advance!(p::Parser)
    token = p.tokens[p.pos]
    p.pos += 1
    return token
end

# expr := term (('+' | '-') term)*
function parse_expr(p::Parser)
    value = parse_term(p)

    while peek(p).kind == :op && (peek(p).text == "+" || peek(p).text == "-")
        op = advance!(p).text
        rhs = parse_term(p)
        value = op == "+" ? value + rhs : value - rhs
    end

    return value
end

# term := factor (('*' | '/') factor)*
function parse_term(p::Parser)
    value = parse_factor(p)

    while peek(p).kind == :op && (peek(p).text == "*" || peek(p).text == "/")
        op = advance!(p).text
        rhs = parse_factor(p)

        if op == "/"
            rhs == 0.0 && error("Division by zero")
            value /= rhs
        else
            value *= rhs
        end
    end

    return value
end

# factor := ('-' | '+') factor | atom
function parse_factor(p::Parser)
    token = peek(p)

    if token.kind == :op && (token.text == "-" || token.text == "+")
        advance!(p)
        value = parse_factor(p)

        return token.text == "-" ? -value : value
    end

    return parse_atom(p)
end

# atom := number | ident | '(' expr ')'
function parse_atom(p::Parser)
    token = advance!(p)

    if token.kind == :num
        value = tryparse(Float64, token.text)
        value === nothing && error("Invalid number: $(token.text)")
        return value

    elseif token.kind == :ident
        haskey(p.vars, token.text) || error("Unknown variable: $(token.text)")
        return p.vars[token.text]

    elseif token.kind == :lparen
        value = parse_expr(p)

        peek(p).kind == :rparen || error("Expected ')'")
        advance!(p)

        return value

    else
        token_text = isempty(token.text) ? "end of expression" : token.text
        error("Unexpected token: $token_text")
    end
end

function eval_expr(expr::AbstractString, vars::Dict{String, Float64})
    tokens = tokenize(expr)
    parser = Parser(tokens, 1, vars)

    value = parse_expr(parser)

    peek(parser).kind == :eof ||
        error("Unexpected token after expression: $(peek(parser).text)")

    return value
end

# ─── Проверка имени переменной ─────────────────────────────────────────────
function isidentifier(s::AbstractString)
    isempty(s) && return false

    chars = collect(s)

    (isletter(chars[1]) || chars[1] == '_') || return false

    return all(c -> isletter(c) || isdigit(c) || c == '_', chars)
end

# ─── Обработка команд ──────────────────────────────────────────────────────
function handle_line(line::AbstractString, vars::Dict{String, Float64})
    command_parts = split(strip(line); limit=2)

    isempty(command_parts) && return "Error: empty command"

    command = command_parts[1]

    if command == "SET"
        length(command_parts) == 2 ||
            return "Error: usage SET name value"

        arguments = split(strip(command_parts[2]))

        length(arguments) == 2 ||
            return "Error: usage SET name value"

        name, value_text = arguments

        isidentifier(name) ||
            return "Error: invalid variable name"

        value = tryparse(Float64, value_text)

        value === nothing && return "Error: invalid number"

        vars[name] = value
        return "OK"

    elseif command == "EVAL"
        length(command_parts) == 2 ||
            return "Error: usage EVAL expression"

        try
            value = eval_expr(strip(command_parts[2]), vars)
            return string(value)
        catch err
            return "Error: $(sprint(showerror, err))"
        end

    elseif command == "VARS"
        length(command_parts) == 1 ||
            return "Error: usage VARS"

        isempty(vars) && return "No variables"

        names = sort!(collect(keys(vars)))

        return join(["$name = $(vars[name])" for name in names], "; ")

    elseif command == "QUIT"
        length(command_parts) == 1 ||
            return "Error: usage QUIT"

        return "BYE"

    else
        return "Error: unknown command"
    end
end

# ─── Обслуживание клиента ─────────────────────────────────────────────────
function serve_client(sock)
    # У каждого клиента собственная таблица переменных.
    vars = Dict{String, Float64}()

    println("Client connected")

    try
        while isopen(sock)
            line = try
                String(readuntil(sock, UInt8('\n'); keep=false))
            catch err
                # EOF или закрытие соединения клиентом.
                if err isa EOFError || err isa IOError || !isopen(sock)
                    break
                end

                rethrow()
            end

            text = strip(line)

            isempty(text) && continue

            result = handle_line(text, vars)

            write(sock, result * "\n")
            flush(sock)

            result == "BYE" && break
        end

    catch err
        println("Client error: $(sprint(showerror, err))")

    finally
        close(sock)
        println("Client disconnected")
    end
end

# ─── Запуск TCP-сервера ────────────────────────────────────────────────────
function main(port::Int=4000)
    server = listen(port)

    println("Calculator server listening on port $port...")

    try
        while true
            sock = accept(server)
            @async serve_client(sock)
        end

    finally
        close(server)
    end
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(4000)
end