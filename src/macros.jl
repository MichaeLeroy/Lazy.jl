# Threading macros

export @>, @>>, @as, @switch, @or, @dotimes, @once_then

isexpr(x::Expr, ts...) = x.head in ts
isexpr{T}(x::T, ts...) = T in ts

subexprs(ex) = filter(x -> !isexpr(x, :line), ex.args)

macro switch (test, exprs)
  @assert isexpr(exprs, :block) "@switch requires a begin block"
  exprs = subexprs(exprs)
  length(exprs) == 0 && return nothing
  length(exprs) == 1 && return esc(exprs[1])

  test_expr(test, val) =
    test == :_      ? val :
    isa(test, Expr) ? :(let _ = $val; $test; end) :
                      :($test==$val)

  thread(test, val, yes, no) = :($(test_expr(test, val)) ? $yes : $no)
  thread(test, val, yes) = thread(test, val, yes, :(error($"No match for $test in @switch")))
  thread(test, val, yes, rest...) = thread(test, val, yes, thread(test, rest...))

  esc(thread(test, exprs...))
end

macro > (exs...)
  thread(x) = isexpr(x, :block) ? thread(subexprs(x)...) : x

  thread(x, ex) =
    isexpr(ex, Symbol, :->)       ? Expr(:call, ex, x) :
    isexpr(ex, :call, :macrocall) ? Expr(ex.head, ex.args[1], x, ex.args[2:end]...) :
    isexpr(ex, :block)            ? thread(x, subexprs(ex)...) :
                                    error("Unsupported expression $ex in @>")

  thread(x, exs...) = reduce(thread, x, exs)

  esc(thread(exs...))
end

macro >> (exs...)
  thread(x) = isexpr(x, :block) ? thread(subexprs(x)...) : x

  thread(x, ex) =
    isexpr(ex, Symbol, :->)       ? Expr(:call, ex, x) :
    isexpr(ex, :call, :macrocall) ? Expr(ex.head, ex.args..., x) :
    isexpr(ex, :block)            ? thread(x, subexprs(ex)...) :
                                    error("Unsupported expression $ex in @>>")

  thread(x, exs...) = reduce(thread, x, exs)

  esc(thread(exs...))
end

macro as (exs...)
  thread(as, x) = isexpr(x, :block) ? thread(as, subexprs(x)...) : x

  thread(as, x, ex) =
    isexpr(ex, Symbol, :->) ? Expr(:call, ex, x) :
    isexpr(ex, :block)      ? thread(as, x, subexprs(ex)...) :
    :(let $as = $x
        $ex
      end)

  thread(as, x, exs...) = reduce((x, ex) -> thread(as, x, ex), x, exs)

  esc(thread(exs...))
end

macro or (exs...)
  thread(x) = isexpr(x, :block) ? thread(subexprs(x)...) : x

  thread(x, xs...) =
    :(let x = $(esc(x))
        !(x == nothing || x == false) ? x : $(thread(xs...))
      end)

  thread(exs...)
end

macro dotimes(n, body)
  quote
    for i = 1:$(esc(n))
      $(esc(body))
    end
  end
end

macro once_then(expr::Expr)
  @assert expr.head == :while
  esc(quote
    $(expr.args[2]) # body of loop
    $expr # loop
  end)
end