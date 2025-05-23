(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

(** Expressions

    Pure (heap-independent) expressions are complex arithmetic, bitwise-logical, etc. operations
    over literal values and registers. *)

open! NS

type op1 =
  | Signed of {bits: int}
      (** [Ap1 (Signed {bits= n}, dst, arg)] is [arg] interpreted as an [n]-bit signed integer and
          injected into the [dst] type. That is, it two's-complement--decodes the low [n] bits of
          the infinite two's-complement encoding of [arg]. The injection into [dst] is a no-op, so
          [dst] must be an integer type with bitwidth at least [n]. This expression can also be
          lifted to operate element-wise over arrays. When [dst] is an array [arg] must also be an
          array of the same length, with element types satisfying the aforementioned constraints on
          integer types. *)
  | Unsigned of {bits: int}
      (** [Ap1 (Unsigned {bits= n}, dst, arg)] is [arg] interpreted as an [n]-bit unsigned integer
          and injected into the [dst] type. That is, it unsigned-binary--decodes the low [n] bits of
          the infinite two's-complement encoding of [arg]. The injection into [dst] is a no-op, so
          [dst] must be an integer type with bitwidth greater than [n]. This expression can be
          lifted to arrays, as described for [Signed] just above. *)
  | Convert of {src: LlairTyp.t}
      (** [Ap1 (Convert {src}, dst, arg)] is [arg] converted from type [src] to type [dst], possibly
          with loss of information. The [src] and [dst] types must be [LlairTyp.convertible] and
          must not both be [Integer] types. *)
  | Splat  (** Iterated concatenation of a single byte *)
  | Select of int  (** Select an index from a record *)
[@@deriving compare, equal, sexp]

type op2 =
  | Eq  (** Equal test *)
  | Dq  (** Disequal test *)
  | Gt  (** Greater-than test *)
  | Ge  (** Greater-than-or-equal test *)
  | Lt  (** Less-than test *)
  | Le  (** Less-than-or-equal test *)
  | Ugt  (** Unsigned greater-than test *)
  | Uge  (** Unsigned greater-than-or-equal test *)
  | Ult  (** Unsigned less-than test *)
  | Ule  (** Unsigned less-than-or-equal test *)
  | Ord  (** Ordered test (neither arg is nan) *)
  | Uno  (** Unordered test (some arg is nan) *)
  | Add  (** Addition *)
  | Sub  (** Subtraction *)
  | Mul  (** Multiplication *)
  | Div  (** Division, for integers result is truncated toward zero *)
  | Rem
      (** Remainder of division, satisfies [a = b * div a b + rem a b] and for integers [rem a b]
          has same sign as [a], and [|rem a b| < |b|] *)
  | Udiv  (** Unsigned division *)
  | Urem  (** Remainder of unsigned division *)
  | And  (** Conjunction, boolean or bitwise *)
  | Or  (** Disjunction, boolean or bitwise *)
  | Xor  (** Exclusive-or, bitwise *)
  | Shl  (** Shift left, bitwise *)
  | Lshr  (** Logical shift right, bitwise *)
  | Ashr  (** Arithmetic shift right, bitwise *)
  | Update of int  (** Constant record with updated index *)
[@@deriving compare, equal, sexp]

type op3 = Conditional  (** If-then-else *) [@@deriving compare, equal, sexp]

type opN = Record  (** Record (array / struct) constant *) [@@deriving compare, equal, sexp]

type t = private
  | Reg of {id: int; name: string; typ: LlairTyp.t}  (** Virtual register *)
  | Global of {name: string; is_constant: bool; typ: LlairTyp.t [@ignore]}  (** Global constant *)
  | FuncName of {name: string; typ: LlairTyp.t [@ignore]; unmangled_name: string option [@ignore]}
  | Label of {parent: string; name: string}
      (** Address of named code block within parent function *)
  | Integer of {data: Z.t; typ: LlairTyp.t}  (** Integer constant *)
  | Float of {data: string; typ: LlairTyp.t}  (** Floating-point constant *)
  | Ap1 of op1 * LlairTyp.t * t
  | Ap2 of op2 * LlairTyp.t * t * t
  | Ap3 of op3 * LlairTyp.t * t * t * t
  | ApN of opN * LlairTyp.t * t iarray
[@@deriving compare, equal, sexp]

val pp : t pp

val string_of_exp : t -> string option

include Invariant.S with type t := t

val demangle : (string -> string option) ref

(** Exp.Reg is re-exported as Reg *)
module Reg : sig
  type exp := t

  type t = private exp [@@deriving compare, equal, sexp]

  module Set : sig
    include Set.S with type elt := t

    include sig
        type t [@@deriving sexp]
      end
      with type t := t

    val pp : t pp
  end

  module Map : Map.S with type key := t

  module Tbl : HashTable.S with type key := t

  val pp : t pp

  include Invariant.S with type t := t

  val of_exp : exp -> t option

  val to_exp : t -> exp

  val mk : LlairTyp.t -> int -> string -> t

  val id : t -> int

  val name : t -> string

  val typ : t -> LlairTyp.t
end

(** Exp.Global is re-exported as Global *)
module Global : sig
  type exp := t

  type t = private exp [@@deriving compare, equal, sexp]

  module Set : sig
    include Set.S with type elt := t

    include sig
        type t [@@deriving sexp]
      end
      with type t := t

    val pp : t pp
  end

  val pp : t pp

  include Invariant.S with type t := t

  val of_exp : exp -> t option

  val mk : LlairTyp.t -> string -> bool -> t

  val name : t -> string

  val typ : t -> LlairTyp.t
end

(** Exp.FuncName is re-exported as FuncName *)
module FuncName : sig
  type exp := t

  type t = private exp [@@deriving compare, equal, sexp]

  module Map : Map.S with type key := t

  module Tbl : HashTable.S with type key := t

  val pp : t pp

  include Invariant.S with type t := t

  val of_exp : exp -> t option

  val mk : unmangled_name:string option -> LlairTyp.t -> string -> t

  val counterfeit : string -> t
  (** [compare] ignores [FuncName.typ], so it is possible to construct [FuncName]s using a dummy
      type that compare equal to their genuine counterparts. *)

  val name : t -> string

  val unmangled_name : t -> string option

  val typ : t -> LlairTyp.t
end

(** Construct *)

(* registers *)
val reg : Reg.t -> t

(* constants *)
val funcname : FuncName.t -> t

val global : Global.t -> t

val label : parent:string -> name:string -> t

val null : t

val bool : bool -> t

val true_ : t

val false_ : t

val integer : LlairTyp.t -> Z.t -> t

val float : LlairTyp.t -> string -> t

(* type conversions *)
val signed : int -> t -> to_:LlairTyp.t -> t

val unsigned : int -> t -> to_:LlairTyp.t -> t

val convert : LlairTyp.t -> to_:LlairTyp.t -> t -> t

(* comparisons *)
val eq : ?typ:LlairTyp.t -> t -> t -> t

val dq : ?typ:LlairTyp.t -> t -> t -> t

val gt : ?typ:LlairTyp.t -> t -> t -> t

val ge : ?typ:LlairTyp.t -> t -> t -> t

val lt : ?typ:LlairTyp.t -> t -> t -> t

val le : ?typ:LlairTyp.t -> t -> t -> t

val ugt : ?typ:LlairTyp.t -> t -> t -> t

val uge : ?typ:LlairTyp.t -> t -> t -> t

val ult : ?typ:LlairTyp.t -> t -> t -> t

val ule : ?typ:LlairTyp.t -> t -> t -> t

val ord : ?typ:LlairTyp.t -> t -> t -> t

val uno : ?typ:LlairTyp.t -> t -> t -> t

(* arithmetic *)
val add : ?typ:LlairTyp.t -> t -> t -> t

val sub : ?typ:LlairTyp.t -> t -> t -> t

val mul : ?typ:LlairTyp.t -> t -> t -> t

val div : ?typ:LlairTyp.t -> t -> t -> t

val rem : ?typ:LlairTyp.t -> t -> t -> t

val udiv : ?typ:LlairTyp.t -> t -> t -> t

val urem : ?typ:LlairTyp.t -> t -> t -> t

(* boolean / bitwise *)
val and_ : ?typ:LlairTyp.t -> t -> t -> t

val or_ : ?typ:LlairTyp.t -> t -> t -> t

(* bitwise *)
val xor : ?typ:LlairTyp.t -> t -> t -> t

val shl : ?typ:LlairTyp.t -> t -> t -> t

val lshr : ?typ:LlairTyp.t -> t -> t -> t

val ashr : ?typ:LlairTyp.t -> t -> t -> t

(* if-then-else *)
val conditional : LlairTyp.t -> cnd:t -> thn:t -> els:t -> t

(* sequences *)
val splat : LlairTyp.t -> t -> t

(* records (struct / array values) *)
val record : LlairTyp.t -> t iarray -> t

val select : LlairTyp.t -> t -> int -> t

val update : LlairTyp.t -> rcd:t -> int -> elt:t -> t

(** Traverse *)

val fold_exps : t -> 's -> f:(t -> 's -> 's) -> 's

val fold_regs : t -> 's -> f:(Reg.t -> 's -> 's) -> 's

(** Query *)

val is_true : t -> bool

val is_false : t -> bool

val typ_of : t -> LlairTyp.t
