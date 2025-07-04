(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd
open Llair

val translate : source_file:string -> Program.t -> Textual.Lang.t -> Textual.Module.t
