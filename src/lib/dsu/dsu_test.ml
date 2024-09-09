open Core_kernel
open! Alcotest
open Dsu

(* Mock data module for testing *)
module MockData : Data with type t = int = struct
  type t = int

  let merge a b = a + b
end

(* Instantiate the DSU with int keys and mock data *)
module IntKeyDsu = Dsu (Int) (MockData)

(* Test creating a new DSU *)
let test_create () =
  let dsu = IntKeyDsu.create () in
  Alcotest.(check (option int)) "empty DSU" (IntKeyDsu.get ~key:1 dsu) None

(* Test adding a single element to the dsu *)
let test_add () =
  let dsu = IntKeyDsu.create () in
  IntKeyDsu.add_exn ~key:1 ~value:1 dsu ;
  Alcotest.(check (option int))
    "added element" (IntKeyDsu.get ~key:1 dsu) (Some 1)

(* Test adding an array of arbitrary elements *)
let test_add_array () =
  let dsu = IntKeyDsu.create () in
  (* generate a qcheck array of ints *)
  let arr = QCheck.Gen.(generate1 (array_size (int_range 100 200) int)) in
  (* log the arrays size *)
  Printf.printf "Array size: %d\n" (Array.length arr) ;

  (* add each element to the dsu *)
  Array.iter arr ~f:(fun x -> IntKeyDsu.add_exn ~key:x ~value:x dsu) ;
  Array.iter arr ~f:(fun x ->
      Alcotest.(check (option int))
        "added element" (IntKeyDsu.get ~key:x dsu) (Some x) )

let test_reallocation () =
  let dsu = IntKeyDsu.create () in
  let arr_size = QCheck.Gen.(int_range 50 60) in
  let arr = QCheck.Gen.(generate1 (array_size arr_size int)) in
  (* a ref to an array size int*)
  let arr_size = ref (Array.length arr) in
  Array.iter arr ~f:(fun x ->
      match IntKeyDsu.get ~key:x dsu with
      | Some _ ->
          (* in case qcheck generates repeats we don't want the test to fail *)
          arr_size := !arr_size - 1
      | None ->
          IntKeyDsu.add_exn ~key:x ~value:x dsu ) ;
  Alcotest.(check int)
    "verifying capacity is 64 i.e min capacity" (IntKeyDsu.capacity dsu) 64 ;
  Alcotest.(check int)
    (* we add 1 to account for the default 0 element used for dynamic deletions in the dsu *)
    "verifying occupancy is the size of the array additions" (!arr_size + 1)
    (IntKeyDsu.occupancy dsu) ;
  (* add 400 more items for resize *)
  (* generates on a normal distribution so there are low risk of repeats to skip allocation *)
  let arr = QCheck.Gen.(generate1 (array_size (int_range 400 401) int)) in
  Array.iter arr ~f:(fun x -> IntKeyDsu.add_exn ~key:x ~value:x dsu) ;
  Alcotest.(check int)
    "verifying capacity is 512 meaning there have been 4 re-allocations"
    (IntKeyDsu.capacity dsu) 512

(* alcotest harness *)
let tests =
  [ ("test_create", `Quick, test_create)
  ; ("test_add", `Quick, test_add)
  ; ("test_add_array", `Quick, test_add_array)
  ; ("test_reallocation", `Quick, test_reallocation)
  ]

let () = run "dsu" [ ("dsu", tests) ]
