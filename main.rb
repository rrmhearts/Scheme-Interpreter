#!/usr/bin/ruby
#
# A simplified scheme interpreter in Ruby.  Wow.

# ---------------------------------------------------------------------
# Scheme data types
# ---------------------------------------------------------------------

#  In case we get some Ruby data type that is not a Scheme data type
#  in a Scheme expression, make sure all non-scheme objects evaluate
#  to false.
class Object
  def eval(scope)
    false
  end

  def scheme_type?
    false
  end
end

# For Scheme numbers (we will only support integer numbers for this
# subset of scheme) we will simply expand upon Ruby's integer class.
class Integer

  # Integers are self-evaluating
  def eval(scope)
    self
  end

  # No need for deep copies of integers, Ruby takes care of this
  def dup
    self
  end

  # For argument validation code
  def scheme_type?
    true
  end
end

# We'll differentiate Scheme strings from Ruby strings slightly.
# The primary difference will be that Scheme strings print with
# quotation marks around them.
class SchemeString < String
  def eval(scope)
    self
  end

  def scheme_type?
    true
  end

  def to_s
    '"' + self + '"'
  end
end

# We'll use Ruby's true and false classes for Scheme's booleans.
# We just need to make sure they print out correctly and self
# evaluate.
class TrueClass
  def to_s
    "#t"
  end

  def dup
    self
  end

  def eval(scope)
    self
  end

  def scheme_type?
    true
  end
end

class FalseClass
  def to_s
    "#f"
  end

  def dup
    self
  end

  def eval(scope)
    self
  end

  def scheme_type?
    true
  end
end

# We will use Ruby's nil for Scheme's null pointer.  We need
# to make sure nil is self-evaluating and prints as ().
class NilClass
  def eval(scope)
    self
  end

  def eval_args(scope)
    self
  end

  def dup
    self
  end

  def to_s
    "()"
  end

  # Since a null pointer is a valid list in scheme, we need to make
  # sure that a few list functions are supported by NilClass
  def count
    0
  end

  def to_s_list
    ""
  end

  def scheme_type?
    true
  end
end

# The first, and most important "pure" Scheme class to be implemented
# is the dotted-pair or "cons box".  This is a pretty simple data
# structure, but there are a number of support functions included here
# to make tasks like evaluating argument lists easier.
class Pair

  attr_reader :car, :cdr

  def initialize(car, cdr)
    if (car.scheme_type? and cdr.scheme_type?)
      @car = car
      @cdr = cdr
    else
      raise "Non-Scheme object found its way to Pair.initialize"
    end
  end

  # When we copy a pair, we need a deep (recursive) copy, so that
  # we can duplicate lists and other complex pair structures.  This
  # means that all Scheme data types must provide dup()
  def dup
    Pair.new(@car.dup, @cdr.dup)
  end

  # Implement Scheme style printing of lists and pairs.
  def to_s

    # If the cdr is another pair, then this is a list-type structure.
    # In other words we would have a
    # "(.(" substring in the printout.  Scheme suppresses those
    # for pretty list printing, so we will as well using
    # to_s_list:
    if (@cdr.kind_of?(Pair))
      "(" + @car.to_s + " " + @cdr.to_s_list + ")"

      # If the cdr is nil, that is still a valid list, so we do
      # the same as above.
    elsif (@cdr.kind_of?(NilClass))
      "(" + @car.to_s + @cdr.to_s_list + ")"

      # If the cdr is any other scheme type, we have a dotted pair:
    else
      "(" + @car.to_s + " . " + @cdr.to_s + ")"
    end
  end

  # This functions supports printing scheme objects that are part
  # of a list.  All objects inside of a list get their ()'s omitted
  # for pretty list printing.
  def to_s_list
    if (@cdr.kind_of?(Pair))
      @car.to_s + " " + @cdr.to_s_list
    elsif (@cdr.kind_of?(NilClass))
      @car.to_s + @cdr.to_s_list
    else
      @car.to_s + " . " + @cdr.to_s
    end
  end

  # Check if a Pair is a proper list.  If all the cdr
  # values in a nested set of Pairs are either Pairs or nil, then
  # it is a proper list.  The check is done recursively.
  def list?
    if (@cdr.kind_of?(NilClass))
      true
    elsif(@cdr.kind_of?(Pair))
      @cdr.list?
    else
      false
    end
  end

  # Since we are going to have a lot of proper lists (for argument
  # lists, for example) we define the count function to let us know how
  # many items are in a flat list.
  def count

    # Don't try to count a non-list:
    if (!list?)
      raise "Cannot count a non-list pair"
    end

    # Counting for a proper list is done recursively
    if (!@cdr)
      1
    else
      1 + @cdr.count
    end
  end

  # The Ruby-style "each" iterator is handy for proper lists
  def each

    # Only use each on proper lists:
    if (!list?)
      raise "Iteration only works over proper lists"

      # The iterator is executed recursively, of course.
    else
      current = self
      while (current != nil)
        yield current.car
        current = current.cdr
      end
    end
  end

  def scheme_type?
    true
  end

  # Much of the meat of the Scheme engine is implemented here in
  # the eval method for class Pair.  The parser will store each
  # valid Scheme expression as a list (nested set of Pairs), and then
  # call eval to evaluate the list.  The parser will always call
  # eval with the $global scope, but eval may be called with other
  # scopes by (for example) the LetFunction.  For a more complete
  # discussion of scope, see class Scope, below.
  def eval(scope)

    # All valid Scheme forms are proper lists, so check that first.
    if (!list?)
      raise "Syntax error"
    end

    # If we have a list, we need to check if the first item in the
    # list evaluates to a function or to a special form.
    first = @car.eval(scope)
    arglist = @cdr

    # If this is a function call, evaluate every item in the
    # rest of the form, and then invoke the function with the
    # resulting argument list
    if (first.kind_of?(Function))
      first.invoke(arglist.eval_args(scope))

      # If this is a special form, invoke the special form with the
      # unaltered argument list.  If the special form needs to evaluate
      # any of its arguments, it will have to do it itself.
    elsif (first.kind_of?(SpecialForm))
      first.invoke(arglist, scope)
    else
      raise "Expected function or special form, got #{@car.to_s}"
    end

  end

  # Eval_args is intended primarily for evaluating argument lists.  It
  # expects a list, and it returns a new list containing the evaluation
  # of each item in the input list.
  def eval_args(scope)
    if (!list?)
      raise "Syntax error in argument list"
    end
    Pair.new(@car.eval(scope), @cdr.eval_args(scope))
  end

end

# A scheme scope (or environment) is essentially a set of symbol
# bindings.  Here, we will implement the scope as a hash with symbol
# names (Strings) as the keys, and symbol values (any valid Scheme
# object) as the values.
#
# The parent link provides nested scopes and variable shadowing.
# If a symbol cannot be evaluated in the current scope, the parent
# scope is checked.
class Scope < Hash
  attr_reader :parent

  def initialize(parent)
    super()
    @parent = parent
  end

  # When looking up a value, check the parent scope if the current
  # scope does not define the symbol
  def [](key)

    # First, check the current scope using Ruby's hash lookup
    # function
    if(value = super)
      value

      # If the current scope does not define the symbol and there is
      # no parent scope, then we have an undefined symbol error.  If
      # there is a parent scope, check there recursively.
    elsif(@parent)
      @parent[key]
    else
      raise "Undefined symbol: #{key}"
    end
  end
end

# A Scheme symbol contains a string identifier.  The primary
# change from the string class is in eval.  SchemeStrings are
# self evaluating.  SchemeSymbols evaluate to the value of the
# symbol in some scope.  To evaluate a SchemeSymbol, you must
# supply a scope to the eval method.
class SchemeSymbol
  attr_reader :identifier

  def initialize(identifier)
    @identifier = identifier
  end

  def dup
    new(@identifier.dup)
  end

  def eval(scope)
    scope[@identifier]
  end

  def scheme_type?
    true
  end

  def to_s
    @identifier
  end
end

# To Do: In retrospect, class Function should be the only Function
# class. Scheme functions should be objects of class function with the
# Ruby code passed to initialize and stored in a proc object. Thus we
# would always only have one Ruby object per Scheme function. As is,
# each Function is a subclass of class Function with, hopefully, only
# one instance.

# Scheme functions are self-evaluating.  The work of the function
# is done in invoke, which must be defined for each function
# individually.  Invoke is pass an already-evaluated argument
# list.
class Function

  def eval(scope)
    self
  end

  # This method should be overrident for each intrinsic function.
  def invoke(arglist)
    raise "Unimplemented intrinsic function"
  end

  def dup
    self	# I don't think deep copies are necessary for functions.
  end

  def scheme_type?
    true
  end

  def to_s
    "#" + self.class.to_s
  end

end

# To Do:  Special Forms should also be class with code stored in a proc
# object.  See class Function.

# As with intrinsic functions, the work for each special form is done
# by invoke().  For special forms, invoke is passed an unevaluated
# argument list.
class SpecialForm

  def eval(scope)
    self
  end

  def invoke(arglist, scope)
    raise "Unimplemented special form"
  end

  # I don't think deep copies are necessary for special forms
  def dup
    self
  end

  def to_s
    "#" + self.class.to_s
  end

  def scheme_type?
    true
  end
end

# Closures are returned by Schemes (lambda) form.  Each
# closure consists of a static scope, a formal parameter
# list, and some code to execute.  The code should be
# a Scheme list.  Here we will only support functions that
# expect a fixed number of formal parameters.
class Closure < Function

  # Probably should do more error checking here
  def initialize(scope, paramlist, code)
    @staticScope = scope
    @paramlist = paramlist
    @code = code
  end

  # The arity of a funciton is the number of formal parameters
  # it expects.
  def arity
    @paramlist.count
  end

  # When you invoke a Closure, the following things happen:
  # 1) The arguments are assigned to the formal parameters.  Here
  #    we create a new local scope with symbols for each formal
  #    parameter, and the values from the argument list.  Since
  #    A Closure is a subclass of Function, the arguments will already
  #    be evaluated.  The scope in which the closure is invoked becomes
  #    the parent of this new local scope.
  # 2) The the code (a Scheme list) is evaluated in the new local
  #    scope.  Thus, any references to formal parameters in the code
  #    are symbols which evaluate to the values from the (pre-evaluated)
  #    argument list.
  def invoke(arglist)

    # Make sure the closure was called with the right number
    # of arguments:
    argcount = arglist.count
    if (argcount != arity)
      raise "Lambda function expected #{arity} arguments, got #{argcount}"
    end

    # Assign argument values to formal parameters as symbols in a
    # new local scope
    localScope = Scope.new(@staticScope)
    currentArg = arglist
    currentParam = @paramlist
    while (currentArg and currentParam)
      localScope[currentParam.car.identifier] = currentArg.car
      currentArg = currentArg.cdr
      currentParam = currentParam.cdr
    end

    # Evaluate the code in the current scope
    @code.eval(localScope)
  end

end

#----------------------------------------------------------------------
# Special Form Definitions
#----------------------------------------------------------------------

# If provides for conditional execution.  It expects three arguments,
# a test, an expression to execute if the test returns true (actually,
# anything but false) and an expression to execute if the test
# returns false.
class IfForm < SpecialForm

  def invoke(arglist, scope)

    # Check the syntax
    if (arglist.list? && arglist.count == 3)

      test = arglist.car
      trueBranch = arglist.cdr.car
      falseBranch = arglist.cdr.cdr.car

      if (test.eval(scope))
        trueBranch.eval(scope)
      else
        falseBranch.eval(scope)
      end
    else
      raise "Syntax error in IF"
    end
  end
end


# Define expects two arguments.  The first argument is a symbol,
# the second argument is evaluated and assigned to the symbol
# **in the $global scope**.
class DefineForm < SpecialForm

  # If the first argument is a symbol and the second is a valid
  # scheme type, then assign the value to the symbol in the
  # $global scope.  Otherwise complain.
  def invoke(arglist, scope)
    if (arglist.list? && \
        arglist.count == 2 && \
        arglist.car.kind_of?(SchemeSymbol) && \
        arglist.cdr.car.scheme_type?)
      $global[arglist.car.identifier] = arglist.cdr.car.eval(scope)
    else
      raise "Syntax error in define"
    end
  end
end

# Let could be implemented as syntactic sugar for lambda.  Here
# I'll do it independently of lambda.  Let expects two lists
# as arguments.  The first list contains sublists of the form
# (variable value).  Let creates a new scope and
# creates a symbol assignment for each (variable value) pair.  The
# variables are not evaluated (they should be Scheme symbols), the
# values are evaluated.  The second argument to (let) is a list
# with the code to be evaluated in the new local scope.
class LetForm < SpecialForm
  def invoke(arglist, scope)

    # There should be two arguments, a list of variable assignments
    # and the code to execute.
    if (arglist.list? && \
        arglist.count == 2)

      definitions = arglist.car
      code = arglist.cdr.car

      # Create a new local scope with the new definitions
      newLocal = Scope.new(scope)

      # For each definition
      currentDefinition = definitions
      while (currentDefinition)

        # Check the syntax (two items in the list)
        if (!currentDefinition.car.list? or \
            currentDefinition.car.count != 2)
          raise "Syntax error in let"

        # If the syntax is OK, make sure the first item is a
        # SchemeSymbol, and the second
        # is a valid Scheme value of some type
        else
          newSymbol = currentDefinition.car.car
          newValue = currentDefinition.car.cdr.car.eval(scope)

          if (!newSymbol.kind_of?(SchemeSymbol) or \
              !newValue.scheme_type?)
            raise "Internal/parse error in let definition(s)"
          end

          # If everything is OK, define the symbol
          # in the new local Scope
          newLocal[newSymbol.identifier] = newValue
        end

        # Move on to the next definition
        currentDefinition = currentDefinition.cdr
      end


      # Finally, evaluate the code in the new local scope
      code.eval(newLocal)

      # If there are not two list arguments, complain
    else
      raise "Syntax error in let"
    end
  end
end

# The special form Lambda creates a new closure.  The real work
# is done by the Closure class.  Lambda simply checks its parameters
# and passes them to Closure.new
class LambdaForm < SpecialForm

  # Lambda expects two arguments, a formal parameter list and
  # the code to execute.
  def invoke(arglist, scope)
    if (arglist.list? && arglist.count == 2)
      paramlist = arglist.car
      code = arglist.cdr.car

      # If the arguments are OK, create a closure and return it
      Closure.new(scope, paramlist, code)

      # Otherwise complain
    else
      raise "Syntax error in lambda"
    end
  end
end

#----------------------------------------------------------------------
# Intrinsic Function Definitions:
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# Math functions
#  Each of the following math functions implements a built-in scheme
#  function, but for integer values only.  Some of them (actually,
#  all but +) differ slightly in the number of arguments they will
#  accept, but are largely the same as the PLT scheme implementations.
#----------------------------------------------------------------------

class AddFunction < Function
  def invoke(arglist)
    if (arglist.list?)
      sum = 0
      arglist.each{|item| sum += item.to_i}
      return sum
    else
      raise "+ expects a flat list of integer arguments"
    end
  end
end

class SubtractFunction < Function
  def invoke(arglist)
    if (arglist.list? and arglist.count >= 2)
      difference = arglist.car.to_i
      arglist.cdr.each{|item| difference -= item.to_i}
      return difference
    else
      raise "- expects a flat list of at least two integer arguments"
    end
  end
end

class MultiplyFunction < Function
  def invoke(arglist)
    if (arglist.list? and arglist.count >= 2)
      product = arglist.car.to_i
      arglist.cdr.each{|item| product *= item.to_i}
      return product
    else
      raise "- expects a flat list of at least two integer arguments"
    end
  end
end

class DivideFunction < Function
  def invoke(arglist)
    if (arglist.list? and arglist.count >= 2)
      quotient = arglist.car.to_i
      arglist.cdr.each{|item| quotient /= item.to_i}
      return quotient
    else
      raise "- expects a flat list of at least two integer arguments"
    end
  end
end

# Equal tests for simple equality.  It is a bit more powerful
# than MZscheme's = operator
class EqualFunction < Function
  def invoke(arglist)
    if (arglist.list? and arglist.count == 2)
      if (arglist.car == arglist.cdr.car)
        true
      else
        false
      end
    else
      raise "Syntax error in ="
    end
  end
end

# Cons simply returns a new Pair.  Should probably make sure that
# car and cdr are both valid scheme objects.
class ConsFunction < Function
  def invoke(arglist)
    if (arglist.list? and arglist.count == 2)
      Pair.new(arglist.car, arglist.cdr.car)
    else
      raise "Cons expected two arguments"
    end
  end
end

# Car expects a list containing one Pair,
# it returns the car of that pair.
class CarFunction < Function
  def invoke(arglist)
    if (arglist.list? and arglist.count == 1)
      arglist.car.car
    else
      raise "Car expects a Pair as its argument"
    end
  end
end

# Cdr expects a list containing one Pair,
# it returns the cdr of that pair.
class CdrFunction < Function
  def invoke(arglist)
    if (arglist.list? and arglist.count == 1)
      arglist.car.cdr
    else
      raise "Cdr expects a Pair as its argument"
    end
  end
end

# List expects a flat list of arguments, it
# returns a new list containing all the arguments.
# List uses Pair.dup so that the new list is not
# linked to the previous arguments.
class ListFunction < Function
  def invoke(arglist)
    if (arglist.list?)
      arglist.dup
    else
      raise "(list) expects a flat list of arguments"
    end
  end
end

#-----------------------------------------------------------------------
# Debugging functions:  Only for internal use
#-----------------------------------------------------------------------
def list(*args)

  if (args.size == 0)
    nil
  else
    first = args.shift
    if (!first.scheme_type?)
      raise "Invalid scheme type for function list"
    else
      Pair.new(first, list(*args))
    end
  end
end

#----------------------------------------------------------------------
# CREATE THE GLOBAL SCOPE & DEFINE GLOBAL
# SYMBOLS.  Each intrinsic function is instantiated only once, and
# pointed to by a symbol in the $global scope.  If the symbol is
# re-assigned, the intrinsic function is lost.  This is consistant
# with the behavior of MZscheme.  No reserved words here.
#-----------------------------------------------------------------------
$global = Scope.new(nil)
$global['+'] = AddFunction.new
$global['-'] = SubtractFunction.new
$global['*'] = MultiplyFunction.new
$global['/'] = DivideFunction.new
$global['='] = EqualFunction.new
$global['list'] = ListFunction.new
$global['cons'] = ConsFunction.new
$global['car'] = CarFunction.new
$global['cdr'] = CdrFunction.new
$global['define'] = DefineForm.new
$global['let'] = LetForm.new
$global['lambda'] = LambdaForm.new
$global['if'] = IfForm.new

#----------------------------------------------------------------------
# PARSER - The parser is responsible for reading scheme expressions,
#          validating their syntax, and creating a list of Scheme
#          objects that represents the expression.  This parser is
#          very simple and does very little syntax checking.
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# getExpression - Read a single Scheme expression from an input stream
#                 The expression to be read can be a:
#                   String - First character is ", read until the
#                            closing " by calling getString
#                   Token - An integer, boolean, or symbol.  Read
#                           until the next whitespace by calling
#                           getToken.
#                   List - First character is (, read until the closing
#                          ) by calling getList.
#----------------------------------------------------------------------
def getExpression(handle)

  # Skip whitespace
  while (nextChar = handle.read(1) and nextChar =~ /\s/)
  end

  # If we reach eof, return nil
  if (nextChar == nil)
    nextChar

  # Otherwise, get a string, list, or other token
  elsif (nextChar == "(")
    getList(handle)
  elsif (nextChar == '"')
    getString(handle)
  elsif (nextChar == ")")
    raise "Unmatched ')'"

  # If the first character does not indicate that the expression
  # is a string or a list, then unread the first character and
  # call getToken to read the token
  else
    handle.seek(-1, IO::SEEK_CUR)
    getToken(handle)
  end
end

# getList assumes that we have read an opening ( character;
# it reads until the matching close ), creating a Pair
# structure recursively.
def getList(handle)

  # Skip whitespace
  while (nextChar = handle.read(1) and nextChar =~ /\s/)
  end

  # Complain if we reach eof before the end of the list
  if (nextChar == nil)
    raise "Unmatched '('"

    # Termination condition - return a nil when we find the closing )
  elsif (nextChar == ")")
    nil

    # Recursive case:
    # For all other characters, create a pair.  Put the next expression
    # into the car, and then call getList to create a new Pair for
    # the cdr.
  else
    handle.seek(-1, IO::SEEK_CUR)
    list = Pair.new(getExpression(handle), getList(handle))
  end
end

# Get a string
def getString(handle)
  newString = ""

  # Read all characters up to the closing quotation mark
  while (nextChar = handle.read(1) and nextChar != '"')
    newString += nextChar
  end

  # If we hit EOF, then we have an unterminated quote
  if (!nextChar)
    raise "Unterminated string"
  end

  # Return a new SchemeString
  SchemeString.new(newString)

end

# Get a non-string, non-list token
def getToken(handle)
  token = ""

  # Read all characters up to the next whitespace or
  # close paren into the token
  while (nextChar = handle.read(1) and nextChar !~ /[\s)]/)
    token += nextChar
  end

  # If the next character is a closed paren, unread it,
  # so that readExpression will find it.
  if (nextChar == ")")
    handle.seek(-1, IO::SEEK_CUR)
  end

  # Once we have the token, convert it to a SchemeObject
  # and return the object.

  # Integers:
  if (token =~ /^\d+/)
    token.to_i

  # Booleans:
  elsif (token == '#t')
    true
  elsif (token == '#f')
    false

  # Everything else is a symbol:
  else
    SchemeSymbol.new(token.chomp)
  end
end


#----------------------------------------------------------------------
# PARSER MAIN PROGRAM:
#----------------------------------------------------------------------


if (! (ARGV.size == 1))
  puts "Usage: scheme <schemefile>"
  exit
end

# This is the Read, Print, Evaluate
# loop:
File.open(ARGV[0], "r") {|script|
  while(!script.eof?)
    expression = getExpression(script)
    puts expression.to_s
    result = expression.eval($global)
    puts "  => " + result.to_s
  end
}