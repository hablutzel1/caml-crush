(************************* MIT License HEADER ************************************
    Copyright ANSSI (2013-2015)
    Contributors : Ryad BENADJILA [ryadbenadjila@gmail.com],
    Thomas CALDERON [calderon.thomas@gmail.com]
    Marion DAUBIGNARD [marion.daubignard@ssi.gouv.fr]

    This software is a computer program whose purpose is to implement
    a PKCS#11 proxy as well as a PKCS#11 filter with security features
    in mind. The project source tree is subdivided in six parts.
    There are five main parts:
      1] OCaml/C PKCS#11 bindings (using OCaml IDL).
      2] XDR RPC generators (to be used with ocamlrpcgen and/or rpcgen).
      3] A PKCS#11 RPC server (daemon) in OCaml using a Netplex RPC basis.
      4] A PKCS#11 filtering module used as a backend to the RPC server.
      5] A PKCS#11 client module that comes as a dynamic library offering
         the PKCS#11 API to the software.
    There is one "optional" part:
      6] Tests in C and OCaml to be used with client module 5] or with the
         bindings 1]

    Here is a big picture of how the PKCS#11 proxy works:

 ----------------------   --------  socket (TCP or Unix)  --------------------
| 3] PKCS#11 RPC server|-|2] RPC  |<+++++++++++++++++++> | 5] Client library  |
 ----------------------  |  Layer | [SSL/TLS optional]   |  --------          |
           |              --------                       | |2] RPC  | PKCS#11 |
 ----------------------                                  | |  Layer |functions|
| 4] PKCS#11 filter    |                                 |  --------          |
 ----------------------                                   --------------------
           |                                                        |
 ----------------------                                             |
| 1] PKCS#11 OCaml     |                                  { PKCS#11 INTERFACE }
|       bindings       |                                            |
 ----------------------                                       APPLICATION
           |
           |
 { PKCS#11 INTERFACE }
           |
 REAL PKCS#11 MIDDLEWARE
    (shared library)

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.

    Except as contained in this notice, the name(s) of the above copyright holders
    shall not be used in advertising or otherwise to promote the sale, use or other
    dealings in this Software without prior written authorization.

    The current source code is part of the PKCS#11 daemon 3] source tree:
 ---------------------- 
| 3] PKCS#11 RPC server|
 ---------------------- 

    Project: PKCS#11 Filtering Proxy
    File:    src/pkcs11proxyd/server.ml

************************** MIT License HEADER ***********************************)
open Pkcs11_rpc_aux
open Pkcs11
open Rpc_helpers

(* Handling the filter passthrough *)
IFDEF WITHOUT_FILTER THEN
DEFINE CALLP11=Pkcs11
ELSE
DEFINE CALLP11=Frontend
ENDIF

INCLUDE "server_ssl.ml"

(* PKCS#11 functions debug variable *)
let ref_pkcs_debug = ref 0
let ref_daemonize_args = ref ""
IFNDEF WITH_SSL THEN
let libnames_config_ref = ref ""
let filter_config_file_ref = ref ""
ENDIF

(* Debug helper *)
(* This function prints the name of the calling function *)
let debug_print_call function_name = 
  (* Debug *)
  if !ref_pkcs_debug = 1
  then begin
    let s = Printf.sprintf "%s called in process %d" function_name (Unix.getpid()) in
    Netplex_cenv.log `Info s;
  end
  (*********)

(* This function prints the pid and the return value of a PKCS#11 function *)
let debug_print_ret function_name ret_value =
  (* Debug *)
  if !ref_pkcs_debug = 1
  then begin
    let s = Printf.sprintf "%s returned in process %d with %s" function_name (Unix.getpid()) (match_cKR_value ret_value) in
    Netplex_cenv.log `Info s;
  end
  (*********)

(* Basic debug *)
let debug_print function_name in_string =
  (* Debug *)
  if !ref_pkcs_debug = 1
  then begin
    let s = Printf.sprintf "%s in process %d: %s" function_name (Unix.getpid()) in_string in
    Netplex_cenv.log `Info s;
  end
  (*********)

let c_Daemonize (param) =
  debug_print_call "C_Daemonize";
  (* To keep things consistent c_Daemonize can pass through filter as well *)
  let ret = Pkcs11.c_Daemonize param in
  debug_print_ret "C_Daemonize" ret; 
  (Int64.of_nativeint ret)

let c_SetupArch (arch) = 
  debug_print "C_SetupArch peer arch is" (Pkcs11.match_arch_value (Int64.to_nativeint arch)); 
  let ret = CALLP11.c_SetupArch (Int64.to_nativeint arch) in
  debug_print "C_SetupArch server arch is" (Pkcs11.match_arch_value ret); 
  (Int64.of_nativeint ret)

let c_Initialize () = 
  debug_print_call "C_Initialize";
  let ret = CALLP11.c_Initialize () in
  debug_print_ret "C_Initialize" ret; 
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_GetSlotList (token_present, count) = 
  debug_print_call "C_GetSlotList";
  let (ret, slot_list_, count_) = CALLP11.c_GetSlotList (Int64.to_nativeint token_present) (Int64.to_nativeint count) in 
  debug_print_ret "C_GetSlotList" ret; 
  {c_getslotlist_rv = (Int64.of_nativeint ret) ; c_getslotlist_slot_list = (Array.map Int64.of_nativeint slot_list_) ; c_getslotlist_count = (Int64.of_nativeint count_)}


(*************************************************************************) 
let c_Finalize () =
  debug_print_call "C_Finalize";
  let ret = CALLP11.c_Finalize () in
  debug_print_ret "C_Finalize" ret; 
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_GetInfo () =
  debug_print_call "C_GetInfo";
  let (ret, info_) = CALLP11.c_GetInfo () in
  debug_print_ret "C_GetInfo" ret; 
  {c_getinfo_rv = (Int64.of_nativeint ret) ; c_getinfo_info = (ck_info_pkcs11_to_rpc_aux info_) }

(*************************************************************************) 
let c_WaitForSlotEvent (flags) =
  debug_print_call "C_WaitForSlotEvent";
  let (ret, count_) = CALLP11.c_WaitForSlotEvent (Int64.to_nativeint flags) in
  debug_print_ret "C_WaitForSlotEvent" ret; 
  {c_waitforslotevent_rv = (Int64.of_nativeint ret) ; c_waitforslotevent_count = (Int64.of_nativeint count_) }

(*************************************************************************) 
let c_GetSlotInfo (slot_id) = 
  debug_print_call "C_GetSlotInfo";
  let (ret, slot_info_) = CALLP11.c_GetSlotInfo (Int64.to_nativeint slot_id) in
  debug_print_ret "C_GetSlotInfo" ret; 
  {c_getslotinfo_rv = (Int64.of_nativeint ret) ; c_getslotinfo_slot_info = (ck_slot_info_pkcs11_to_rpc_aux slot_info_) }

(*************************************************************************) 
let c_GetTokenInfo (slot_id) = 
  debug_print_call "C_GetTokenInfo";
  let (ret, token_info_) = CALLP11.c_GetTokenInfo (Int64.to_nativeint slot_id) in
  debug_print_ret "C_GetTokenInfo" ret; 
  {c_gettokeninfo_rv = (Int64.of_nativeint ret) ; c_gettokeninfo_token_info = (ck_token_info_pkcs11_to_rpc_aux token_info_)}

(*************************************************************************) 
let c_Login (handle, user_type, pin) = 
  debug_print_call "C_Login";
  let real_pin = (Pkcs11.string_to_char_array pin) in
  let ret = CALLP11.c_Login (Int64.to_nativeint handle) (Int64.to_nativeint user_type) real_pin in
  debug_print_ret "C_Login" ret; 
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_Logout (handle) =
  debug_print_call "C_Logout"; 
  let ret = CALLP11.c_Logout (Int64.to_nativeint handle) in
  debug_print_ret "C_Logout" ret; 
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_OpenSession (slot_id, flags) = 
  debug_print_call "C_OpenSession"; 
  let (ret, session_) = CALLP11.c_OpenSession (Int64.to_nativeint slot_id) (Int64.to_nativeint flags) in
  debug_print_ret "C_OpenSession" ret; 
  {c_opensession_rv = (Int64.of_nativeint ret) ; c_opensession_handle = (Int64.of_nativeint session_) }

(*************************************************************************) 
let c_CloseSession (session) = 
  debug_print_call "C_CloseSession"; 
  let ret = CALLP11.c_CloseSession (Int64.to_nativeint session) in
  debug_print_ret "C_CloseSession" ret; 
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_GetMechanismList (slot_id, count) = 
  debug_print_call "C_GetMechanismList"; 
  let (ret, mech_list_, count_) = CALLP11.c_GetMechanismList (Int64.to_nativeint slot_id) (Int64.to_nativeint count) in 
  debug_print_ret "C_GetMechanismList" ret; 
  {c_getmechanismlist_rv = (Int64.of_nativeint ret) ; c_getmechanismlist_list = (Array.map Int64.of_nativeint mech_list_) ; c_getmechanismlist_count = (Int64.of_nativeint count_)}


(*************************************************************************) 
let c_CloseAllSessions (slot_id) = 
  debug_print_call "C_CloseAllSessions";
  let ret = CALLP11.c_CloseAllSessions (Int64.to_nativeint slot_id) in
  debug_print_ret "C_CloseAllSessions" ret; 
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_GetSessionInfo (session) = 
  debug_print_call "C_GetSessionInfo";
  let (ret, session_info_) = CALLP11.c_GetSessionInfo (Int64.to_nativeint session) in
  debug_print_ret "C_GetSessionInfo" ret; 
  {c_getsessioninfo_rv = (Int64.of_nativeint ret) ; c_getsessioninfo_info = (ck_session_info_pkcs11_to_rpc_aux session_info_) }

(*************************************************************************) 
let c_GetMechanismInfo (slot_id, mechanism_type) = 
  debug_print_call "C_GetMechanismInfo";
  let (ret, mech_info_) = CALLP11.c_GetMechanismInfo (Int64.to_nativeint slot_id) (Int64.to_nativeint mechanism_type) in
  debug_print_ret "C_GetMechanismInfo" ret; 
  {c_getmechanisminfo_rv = (Int64.of_nativeint ret) ; c_getmechanisminfo_info = (ck_mechanism_info_pkcs11_to_rpc_aux mech_info_)}

(*************************************************************************) 
let c_InitPIN (session_handle, pin) = 
  debug_print_call "C_InitPIN";
  let real_pin = (Pkcs11.string_to_char_array pin) in
  let ret = CALLP11.c_InitPIN (Int64.to_nativeint session_handle) real_pin in 
  debug_print_ret "C_InitPIN" ret; 
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_SetPIN (session_handle, old_pin, new_pin) = 
  debug_print_call "C_SetPIN";
  let real_old_pin = (Pkcs11.string_to_char_array old_pin) in
  let real_new_pin = (Pkcs11.string_to_char_array new_pin) in
  let ret = CALLP11.c_SetPIN (Int64.to_nativeint session_handle) real_old_pin real_new_pin in 
  debug_print_ret "C_SetPIN" ret; 
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_SeedRandom (session_handle, seed) = 
  debug_print_call "C_SeedRandom";
  let real_seed = (Pkcs11.string_to_char_array seed) in
  let ret = CALLP11.c_SeedRandom (Int64.to_nativeint session_handle) real_seed in 
  debug_print_ret "C_SeedRandom" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_InitToken (slot_id, so_pin, label) = 
  debug_print_call "C_InitToken";
  let real_label = (Pkcs11.string_to_char_array label) in
  let real_so_pin = (Pkcs11.string_to_char_array so_pin) in
  let ret = CALLP11.c_InitToken (Int64.to_nativeint slot_id) real_so_pin real_label in 
  debug_print_ret "C_InitToken" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_GenerateRandom (session_handle, count) = 
  debug_print_call "C_GenerateRandom";
  let (ret, rand_data_) = CALLP11.c_GenerateRandom (Int64.to_nativeint session_handle) (Int64.to_nativeint count) in 
  debug_print_ret "C_GenerateRandom" ret;
  {c_generaterandom_rv = (Int64.of_nativeint ret) ; c_generaterandom_data = (Pkcs11.char_array_to_string rand_data_) }

(*************************************************************************) 
let c_FindObjectsInit (session_handle, attributes) = 
  debug_print_call "C_FindObjectsInit";
  let real_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 attributes) in 
  let ret = CALLP11.c_FindObjectsInit (Int64.to_nativeint session_handle) real_attributes in 
  debug_print_ret "C_FindObjectsInit" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_FindObjects (session_handle, count) = 
  debug_print_call "C_FindObjects";
  let (ret, objects_, count_) = CALLP11.c_FindObjects (Int64.to_nativeint session_handle) (Int64.to_nativeint count) in 
  debug_print_ret "C_FindObjects" ret;
  {c_findobjects_rv = (Int64.of_nativeint ret) ; c_findobjects_objects = (Array.map Int64.of_nativeint objects_) ; c_findobjects_count = (Int64.of_nativeint count_) }

(*************************************************************************) 
let c_FindObjectsFinal (session_handle) = 
  debug_print_call "C_FindObjectsFinal";
  let ret = CALLP11.c_FindObjectsFinal (Int64.to_nativeint session_handle) in 
  debug_print_ret "C_FindObjectsFinal" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_GenerateKey (session_handle, mechanism, attributes) = 
  debug_print_call "C_GenerateKey";
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in 
  let real_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 attributes) in 
  let (ret, object_handle_) = CALLP11.c_GenerateKey (Int64.to_nativeint session_handle) real_mechanism real_attributes in 
  debug_print_ret "C_GenerateKey" ret;
  {c_generatekey_rv = (Int64.of_nativeint ret) ; c_generatekey_handle = (Int64.of_nativeint object_handle_)}

(*************************************************************************) 
let c_GenerateKeyPair (session_handle, mechanism, pub_attributes, priv_attributes) =
  debug_print_call "C_GenerateKeyPair"; 
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in 
  let real_pub_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 pub_attributes) in 
  let real_priv_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 priv_attributes) in 
  let (ret, pub_handle_, priv_handle_) = CALLP11.c_GenerateKeyPair (Int64.to_nativeint session_handle) real_mechanism real_pub_attributes real_priv_attributes in 
  debug_print_ret "C_GenerateKeyPair" ret;
  {c_generatekeypair_rv = (Int64.of_nativeint ret) ; c_generatekeypair_pubhandle = (Int64.of_nativeint pub_handle_); c_generatekeypair_privhandle = (Int64.of_nativeint priv_handle_)}

(*************************************************************************) 
let c_CreateObject (session_handle, attributes) = 
  debug_print_call "C_CreateObject"; 
  let real_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 attributes) in
  let (ret, handle_) = CALLP11.c_CreateObject (Int64.to_nativeint session_handle) real_attributes in 
  debug_print_ret "C_CreateObject" ret;
  {c_createobject_rv = (Int64.of_nativeint ret) ; c_createobject_handle = (Int64.of_nativeint handle_)}

(*************************************************************************) 
let c_CopyObject (session_handle, object_handle, attributes) = 
  debug_print_call "C_CopyObject"; 
  let real_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 attributes) in
  let (ret, handle_) = CALLP11.c_CopyObject (Int64.to_nativeint session_handle) (Int64.to_nativeint object_handle) real_attributes in 
  debug_print_ret "C_CopyObject" ret;
  {c_copyobject_rv = (Int64.of_nativeint ret) ; c_copyobject_handle = (Int64.of_nativeint handle_)}

(*************************************************************************) 
let c_DestroyObject (session_handle, object_handle) = 
  debug_print_call "C_DestroyObject"; 
  let ret = CALLP11.c_DestroyObject (Int64.to_nativeint session_handle) (Int64.to_nativeint object_handle) in 
  debug_print_ret "C_DestroyObject" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_GetAttributeValue (session_handle, object_handle, attributes) = 
  debug_print_call "C_GetAttributeValue"; 
  let real_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 attributes) in
  let (ret, attributes_) = CALLP11.c_GetAttributeValue (Int64.to_nativeint session_handle) (Int64.to_nativeint object_handle) real_attributes in 
  debug_print_ret "C_GetAttributeValue" ret;
  {c_getattributevalue_rv = (Int64.of_nativeint ret) ; c_getattributevalue_value = (Array.map ck_attribute_pkcs11_to_rpc_aux attributes_) }

(*************************************************************************) 
let c_SetAttributeValue (session_handle, object_handle, attributes) =
  debug_print_call "C_SetAttributeValue";  
  let real_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 attributes) in
  let ret = CALLP11.c_SetAttributeValue (Int64.to_nativeint session_handle) (Int64.to_nativeint object_handle) real_attributes in 
  debug_print_ret "C_SetAttributeValue" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_GetObjectSize (session_handle, object_handle) = 
  debug_print_call "C_GetObjectSize";  
  let (ret, size_) = CALLP11.c_GetObjectSize (Int64.to_nativeint session_handle) (Int64.to_nativeint object_handle) in 
  debug_print_ret "C_GetObjectSize" ret;
  {c_getobjectsize_rv = (Int64.of_nativeint ret) ; c_getobjectsize_size = (Int64.of_nativeint size_)}

(*************************************************************************) 
let c_WrapKey (session_handle, mechanism, wrapping_handle, wrapped_handle) = 
  debug_print_call "C_WrapKey";  
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in 
  let (ret, wrapped_value_) = CALLP11.c_WrapKey (Int64.to_nativeint session_handle) real_mechanism (Int64.to_nativeint wrapping_handle) (Int64.to_nativeint wrapped_handle) in 
  debug_print_ret "C_WrapKey" ret;
  {c_wrapkey_rv = (Int64.of_nativeint ret) ; c_wrapkey_value = (Pkcs11.char_array_to_string wrapped_value_) }

(*************************************************************************) 
let c_UnwrapKey (session_handle, mechanism, unwrapping_handle, wrapped_key, attributes) = 
  debug_print_call "C_UnwrapKey";  
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in 
  let real_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 attributes) in
  let real_wrapped_key = (Pkcs11.string_to_char_array wrapped_key) in
  let (ret, unwrapped_value_) = CALLP11.c_UnwrapKey (Int64.to_nativeint session_handle) real_mechanism (Int64.to_nativeint unwrapping_handle) real_wrapped_key real_attributes in 
  debug_print_ret "C_UnwrapKey" ret;
  {c_unwrapkey_rv = (Int64.of_nativeint ret) ; c_unwrapkey_handle = (Int64.of_nativeint unwrapped_value_) }

(*************************************************************************) 
let c_DeriveKey (session_handle, mechanism, initial_key, attributes) = 
  debug_print_call "C_DeriveKey";  
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in 
  let real_attributes = (Array.map ck_attribute_rpc_aux_to_pkcs11 attributes) in
  let (ret, derived_key_) = CALLP11.c_DeriveKey (Int64.to_nativeint session_handle) real_mechanism (Int64.to_nativeint initial_key) real_attributes in 
  debug_print_ret "C_DeriveKey" ret;
  {c_derivekey_rv = (Int64.of_nativeint ret) ; c_derivekey_handle = (Int64.of_nativeint derived_key_) }

(*************************************************************************) 
let c_DigestInit (session_handle, mechanism) = 
  debug_print_call "C_DigestInit"; 
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in
  let ret = CALLP11.c_DigestInit (Int64.to_nativeint session_handle) real_mechanism in
  debug_print_ret "C_DigestInit" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_Digest (session_handle, data) = 
  debug_print_call "C_Digest"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, digested_) = CALLP11.c_Digest (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_Digest" ret;
  {c_digest_rv = (Int64.of_nativeint ret) ; c_digest_value = (Pkcs11.char_array_to_string digested_) }

(*************************************************************************) 
let c_DigestUpdate (session_handle, data) = 
  debug_print_call "C_DigestUpdate"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let ret = CALLP11.c_DigestUpdate (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_DigestUpdate" ret;
  (Int64.of_nativeint ret)
   
(*************************************************************************) 
let c_DigestFinal (session_handle) = 
  debug_print_call "C_DigestFinal"; 
  let (ret, digested_) = CALLP11.c_DigestFinal (Int64.to_nativeint session_handle) in
  debug_print_ret "C_DigestFinal" ret;
  {c_digestfinal_rv = (Int64.of_nativeint ret) ; c_digestfinal_value = (Pkcs11.char_array_to_string digested_) }

(*************************************************************************) 
let c_DigestKey (session_handle, object_handle) = 
  debug_print_call "C_DigestKey"; 
  let ret = CALLP11.c_DigestKey (Int64.to_nativeint session_handle) (Int64.to_nativeint object_handle) in
  debug_print_ret "C_DigestKey" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_SignInit (session_handle, mechanism, object_handle) = 
  debug_print_call "C_SignInit"; 
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in
  let ret = CALLP11.c_SignInit (Int64.to_nativeint session_handle) real_mechanism (Int64.to_nativeint object_handle) in
  debug_print_ret "C_SignInit" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_Sign (session_handle, data) = 
  debug_print_call "C_Sign"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, signed_) = CALLP11.c_Sign (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_Sign" ret;
  {c_sign_rv = (Int64.of_nativeint ret) ; c_sign_value = (Pkcs11.char_array_to_string signed_) }

(*************************************************************************) 
let c_SignUpdate (session_handle, data) = 
  debug_print_call "C_SignUpdate"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let ret = CALLP11.c_SignUpdate (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_SignUpdate" ret;
  (Int64.of_nativeint ret)
   
(*************************************************************************) 
let c_SignFinal (session_handle) = 
  debug_print_call "C_SignFinal"; 
  let (ret, signed_) = CALLP11.c_SignFinal (Int64.to_nativeint session_handle) in
  debug_print_ret "C_SignFinal" ret;
  {c_signfinal_rv = (Int64.of_nativeint ret) ; c_signfinal_value = (Pkcs11.char_array_to_string signed_) }

(*************************************************************************) 
let c_VerifyInit (session_handle, mechanism, object_handle) = 
  debug_print_call "C_VerifyInit"; 
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in
  let ret = CALLP11.c_VerifyInit (Int64.to_nativeint session_handle) real_mechanism (Int64.to_nativeint object_handle) in
  debug_print_ret "C_VerifyInit" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_Verify (session_handle, data, signed_data ) = 
  debug_print_call "C_Verify"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let real_signed_data = (Pkcs11.string_to_char_array signed_data) in
  let ret = CALLP11.c_Verify (Int64.to_nativeint session_handle) real_data real_signed_data in
  debug_print_ret "C_Verify" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_VerifyUpdate (session_handle, data) = 
  debug_print_call "C_VerifyUpdate"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let ret = CALLP11.c_VerifyUpdate (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_VerifyUpdate" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_VerifyFinal (session_handle, data) = 
  debug_print_call "C_VerifyFinal"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let ret = CALLP11.c_VerifyFinal (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_VerifyFinal" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_EncryptInit (session_handle, mechanism, object_handle) = 
  debug_print_call "C_EncryptInit"; 
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in
  let ret = CALLP11.c_EncryptInit (Int64.to_nativeint session_handle) real_mechanism (Int64.to_nativeint object_handle) in
  debug_print_ret "C_EncryptInit" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_Encrypt (session_handle, data ) = 
  debug_print_call "C_Encrypt"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, encrypted_) = CALLP11.c_Encrypt (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_Encrypt" ret;
  {c_encrypt_rv = (Int64.of_nativeint ret) ; c_encrypt_value = (Pkcs11.char_array_to_string encrypted_) }

(*************************************************************************) 
let c_EncryptUpdate (session_handle, data) = 
  debug_print_call "C_EncryptUpdate"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, encrypted_) = CALLP11.c_EncryptUpdate (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_EncryptUpdate" ret;
  {c_encryptupdate_rv = (Int64.of_nativeint ret) ; c_encryptupdate_value = (Pkcs11.char_array_to_string encrypted_) }

(*************************************************************************) 
let c_EncryptFinal (session_handle) = 
  debug_print_call "C_EncryptFinal"; 
  let (ret, encrypted_) = CALLP11.c_EncryptFinal (Int64.to_nativeint session_handle) in
  debug_print_ret "C_EncryptFinal" ret;
  {c_encryptfinal_rv = (Int64.of_nativeint ret) ; c_encryptfinal_value = (Pkcs11.char_array_to_string encrypted_) }

(*************************************************************************) 
let c_DecryptInit (session_handle, mechanism, object_handle) = 
  debug_print_call "C_DecryptInit"; 
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in
  let ret = CALLP11.c_DecryptInit (Int64.to_nativeint session_handle) real_mechanism (Int64.to_nativeint object_handle) in
  debug_print_ret "C_DecryptInit" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_Decrypt (session_handle, data ) = 
  debug_print_call "C_Decrypt"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, decrypted_) = CALLP11.c_Decrypt (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_Decrypt" ret;
  {c_decrypt_rv = (Int64.of_nativeint ret) ; c_decrypt_value = (Pkcs11.char_array_to_string decrypted_) }

(*************************************************************************) 
let c_DecryptUpdate (session_handle, data) = 
  debug_print_call "C_DecryptUpdate"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, decrypted_) = CALLP11.c_DecryptUpdate (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_DecryptUpdate" ret;
  {c_decryptupdate_rv = (Int64.of_nativeint ret) ; c_decryptupdate_value = (Pkcs11.char_array_to_string decrypted_) }

(*************************************************************************) 
let c_DecryptFinal (session_handle) = 
  debug_print_call "C_DecryptFinal"; 
  let (ret, decrypted_) = CALLP11.c_DecryptFinal (Int64.to_nativeint session_handle) in
  debug_print_ret "C_DecryptFinal" ret;
  {c_decryptfinal_rv = (Int64.of_nativeint ret) ; c_decryptfinal_value = (Pkcs11.char_array_to_string decrypted_) }

(*************************************************************************) 
let c_SignRecoverInit (session_handle, mechanism, object_handle) = 
  debug_print_call "C_SignRecoverInit"; 
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in
  let ret = CALLP11.c_SignRecoverInit (Int64.to_nativeint session_handle) real_mechanism (Int64.to_nativeint object_handle) in
  debug_print_ret "C_SignRecoverInit" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_SignRecover (session_handle, data ) = 
  debug_print_call "C_SignRecover"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, recover_) = CALLP11.c_SignRecover (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_SignRecover" ret;
  {c_signrecover_rv = (Int64.of_nativeint ret) ; c_signrecover_value = (Pkcs11.char_array_to_string recover_) }

(*************************************************************************) 
let c_VerifyRecoverInit (session_handle, mechanism, object_handle) = 
  debug_print_call "C_VerifyRecoverInit"; 
  let real_mechanism = (ck_mechanism_rpc_aux_to_pkcs11 mechanism) in
  let ret = CALLP11.c_VerifyRecoverInit (Int64.to_nativeint session_handle) real_mechanism (Int64.to_nativeint object_handle) in
  debug_print_ret "C_VerifyRecoverInit" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_VerifyRecover (session_handle, data ) = 
  debug_print_call "C_VerifyRecover"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, recover_) = CALLP11.c_VerifyRecover (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_VerifyRecover" ret;
  {c_verifyrecover_rv = (Int64.of_nativeint ret) ; c_verifyrecover_value = (Pkcs11.char_array_to_string recover_) }

(*************************************************************************) 
let c_DigestEncryptUpdate (session_handle, data ) = 
  debug_print_call "C_DigestEncryptUpdate"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, recover_) = CALLP11.c_DigestEncryptUpdate (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_DigestEncryptUpdate" ret;
  {c_digestencryptupdate_rv = (Int64.of_nativeint ret) ; c_digestencryptupdate_value = (Pkcs11.char_array_to_string recover_) }

(*************************************************************************) 
let c_DecryptDigestUpdate (session_handle, data ) = 
  debug_print_call "C_DecryptDigestUpdate"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, recover_) = CALLP11.c_DecryptDigestUpdate (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_DecryptDigestUpdate" ret;
  {c_decryptdigestupdate_rv = (Int64.of_nativeint ret) ; c_decryptdigestupdate_value = (Pkcs11.char_array_to_string recover_) }

(*************************************************************************) 
let c_SignEncryptUpdate (session_handle, data ) = 
  debug_print_call "C_SignEncryptUpdate"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, recover_) = CALLP11.c_SignEncryptUpdate (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_SignEncryptUpdate" ret;
  {c_signencryptupdate_rv = (Int64.of_nativeint ret) ; c_signencryptupdate_value = (Pkcs11.char_array_to_string recover_) }

(*************************************************************************) 
let c_DecryptVerifyUpdate (session_handle, data ) = 
  debug_print_call "C_DecryptVerifyUpdate"; 
  let real_data = (Pkcs11.string_to_char_array data) in
  let (ret, recover_) = CALLP11.c_DecryptVerifyUpdate (Int64.to_nativeint session_handle) real_data in
  debug_print_ret "C_DecryptVerifyUpdate" ret;
  {c_decryptverifyupdate_rv = (Int64.of_nativeint ret) ; c_decryptverifyupdate_value = (Pkcs11.char_array_to_string recover_) }

(*************************************************************************) 
let c_GetOperationState (session_handle) = 
  debug_print_call "C_GetOperationState"; 
  let (ret, state_) = CALLP11.c_GetOperationState (Int64.to_nativeint session_handle) in
  debug_print_ret "C_GetOperationState" ret;
  {c_getoperationstate_rv = (Int64.of_nativeint ret) ; c_getoperationstate_value = (Pkcs11.char_array_to_string state_) }

(*************************************************************************) 
let c_SetOperationState (session_handle, state, encryption_handle, authentication_handle) = 
  debug_print_call "C_SetOperationState"; 
  let real_state = (Pkcs11.string_to_char_array state) in
  let ret = CALLP11.c_SetOperationState (Int64.to_nativeint session_handle) real_state (Int64.to_nativeint encryption_handle) (Int64.to_nativeint authentication_handle) in
  debug_print_ret "C_SetOperationState" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_GetFunctionStatus (session_handle) = 
  debug_print_call "C_GetFunctionStatus"; 
  let ret = CALLP11.c_GetFunctionStatus (Int64.to_nativeint session_handle) in
  debug_print_ret "C_GetFunctionStatus" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
let c_CancelFunction (session_handle) = 
  debug_print_call "C_CancelFunction"; 
  let ret = CALLP11.c_CancelFunction (Int64.to_nativeint session_handle) in
  debug_print_ret "C_CancelFunction" ret;
  (Int64.of_nativeint ret)

(*************************************************************************) 
IFDEF WITHOUT_FILTER THEN
let get_module_config_name (modulename) = 
  let regexpression = 
    if compare modulename "" = 0 then
      Printf.sprintf "\\(^\|.*;\\):\\([^;]*\\);"
    else
      Printf.sprintf ".*%s:\\([^;]*\\);" modulename
  in
  let matching_group = 
    if compare modulename "" = 0 then
      2
    else
      1
  in
  let b = Str.string_match (Str.regexp regexpression) !libnames_config_ref 0 in
  if  b = false then
  begin
    (* Return thet the module has not been found *)
    let s = Printf.sprintf "C_LoadModule in process %d did not match any libname for '%s'!" (Unix.getpid()) modulename in
    Netplex_cenv.log `Err s;
    raise (Failure "Reading configuration");
  end
  else
  begin
    let matchedlib = Str.matched_group matching_group !libnames_config_ref in
    (* Debug *)
    if !ref_pkcs_debug = 1
    then begin
      let s = Printf.sprintf "C_LoadModule aliased '%s' to '%s' in process %d" modulename matchedlib (Unix.getpid()) in
      Netplex_cenv.log `Info s;
    end;
    (matchedlib)
  end;
ELSE
let get_module_config_name (modulename) =
  (modulename)
ENDIF

let c_LoadModule (modulename) = 
  debug_print_call "C_LoadModule";
  let ret =
   (try CALLP11.c_LoadModule (Pkcs11.string_to_char_array (get_module_config_name modulename))
    (* If we have an exception, there is a problem, return an error *)
    with _ -> (Pkcs11.cKR_GENERAL_ERROR)) in
  debug_print_ret "C_LoadModule" ret;
  (Int64.of_nativeint ret)


let setup srv _ =
  Pkcs11_rpc_srv.P.V.bind
    ~proc_c_setuparch: c_SetupArch
    ~proc_c_initialize: c_Initialize
    ~proc_c_getslotlist: c_GetSlotList
    ~proc_c_getinfo: c_GetInfo
    ~proc_c_getslotinfo: c_GetSlotInfo
    ~proc_c_gettokeninfo: c_GetTokenInfo
    ~proc_c_finalize: c_Finalize
    ~proc_c_waitforslotevent: c_WaitForSlotEvent
    ~proc_c_login: c_Login
    ~proc_c_logout: c_Logout
    ~proc_c_opensession: c_OpenSession
    ~proc_c_closesession: c_CloseSession
    ~proc_c_getmechanismlist: c_GetMechanismList
    ~proc_c_closeallsessions: c_CloseAllSessions
    ~proc_c_getsessioninfo: c_GetSessionInfo
    ~proc_c_getmechanisminfo: c_GetMechanismInfo
    ~proc_c_initpin: c_InitPIN
    ~proc_c_setpin: c_SetPIN
    ~proc_c_seedrandom: c_SeedRandom
    ~proc_c_inittoken: c_InitToken
    ~proc_c_generaterandom: c_GenerateRandom
    ~proc_c_findobjectsinit: c_FindObjectsInit
    ~proc_c_findobjects: c_FindObjects
    ~proc_c_findobjectsfinal: c_FindObjectsFinal
    ~proc_c_generatekey: c_GenerateKey 
    ~proc_c_generatekeypair: c_GenerateKeyPair 
    ~proc_c_createobject: c_CreateObject
    ~proc_c_copyobject: c_CopyObject
    ~proc_c_destroyobject: c_DestroyObject
    ~proc_c_getattributevalue: c_GetAttributeValue 
    ~proc_c_setattributevalue: c_SetAttributeValue
    ~proc_c_getobjectsize: c_GetObjectSize
    ~proc_c_wrapkey: c_WrapKey
    ~proc_c_unwrapkey: c_UnwrapKey
    ~proc_c_derivekey: c_DeriveKey
    ~proc_c_digestinit: c_DigestInit
    ~proc_c_digest: c_Digest
    ~proc_c_digestupdate: c_DigestUpdate
    ~proc_c_digestfinal: c_DigestFinal
    ~proc_c_digestkey: c_DigestKey
    ~proc_c_signinit: c_SignInit
    ~proc_c_sign: c_Sign
    ~proc_c_signupdate: c_SignUpdate
    ~proc_c_signfinal: c_SignFinal
    ~proc_c_verifyinit: c_VerifyInit
    ~proc_c_verify: c_Verify
    ~proc_c_verifyupdate: c_VerifyUpdate
    ~proc_c_verifyfinal: c_VerifyFinal
    ~proc_c_encryptinit: c_EncryptInit
    ~proc_c_encrypt: c_Encrypt
    ~proc_c_encryptupdate: c_EncryptUpdate
    ~proc_c_encryptfinal: c_EncryptFinal
    ~proc_c_decryptinit: c_DecryptInit
    ~proc_c_decrypt: c_Decrypt
    ~proc_c_decryptupdate: c_DecryptUpdate
    ~proc_c_decryptfinal: c_DecryptFinal
    ~proc_c_signrecoverinit: c_SignRecoverInit
    ~proc_c_signrecover: c_SignRecover
    ~proc_c_verifyrecoverinit: c_VerifyRecoverInit
    ~proc_c_verifyrecover: c_VerifyRecover
    ~proc_c_digestencryptupdate: c_DigestEncryptUpdate
    ~proc_c_signencryptupdate: c_SignEncryptUpdate
    ~proc_c_decryptdigestupdate: c_DecryptDigestUpdate
    ~proc_c_decryptverifyupdate: c_DecryptVerifyUpdate
    ~proc_c_getoperationstate: c_GetOperationState
    ~proc_c_setoperationstate: c_SetOperationState
    ~proc_c_getfunctionstatus: c_GetFunctionStatus
    ~proc_c_cancelfunction: c_CancelFunction
    ~proc_c_loadmodule: c_LoadModule
    srv

(* WITHOUT SSL *)
IFNDEF WITH_SSL THEN

let socket_config _ = Rpc_server.default_socket_config

IFDEF WITHOUT_FILTER THEN
let configure cf addr =
  (* Handle filter passthrough for the specific C_LoadModule call *)
  let filter_config_file =
    try
      Some (cf # string_param (cf # resolve_parameter addr "filter_config"))
    with
      | Not_found -> (None); in
  if filter_config_file <> None
  then
  begin
      let s = Printf.sprintf "CONFIGURATION: unused option 'filter_config' found in the server configuration file while the server has been compiled with filter passthrough!" in
      Netplex_cenv.log `Info s;
  end;
  let libnames_config =
    try
      cf # string_param (cf # resolve_parameter addr "libnames")
    with
      | Not_found -> failwith "Required parameter libnames is missing! (server compiled with filter passthrough mode)!" in
    libnames_config_ref := libnames_config;
("")
ELSE
let configure cf addr =
  (* Warning if this parameter is present! *)
  let libnames_config =
    try
      Some (cf # string_param (cf # resolve_parameter addr "libnames"))
    with
      | Not_found -> (None); in
  if libnames_config <> None
  then
  begin
      let s = Printf.sprintf "CONFIGURATION: unused option 'libnames' found in the server configuration file while the server has been compiled for using the filter module!" in
      Netplex_cenv.log `Info s;
  end;   
  (* Handle configuration file for the filter *)
  let filter_config_file =
    try
      cf # string_param (cf # resolve_parameter addr "filter_config")
    with
      | Not_found -> failwith "Required parameter filter_config is missing! (this is a path to the filter configuration rules)" in
    filter_config_file_ref := filter_config_file;
("")
ENDIF
ENDIF

IFNDEF WITHOUT_FILTER
THEN
(* Loading modules for Netplex levers *)
module T = struct
  type s = string    (* argument type. Here, the message string *)
  type r = bool      (* result type. Here, whether the lever was successful *)
end
module L = Netplex_cenv.Make_lever(T)
module LV = Netplex_cenv.Make_var_type(L)

IFDEF DAEMONIZE THEN
(** Filter hooks that are defined when we use the filter *)
let custom_hooks =
  ( object
      inherit Netplex_kit.empty_processor_hooks()

      val mutable server_shutdown_lever = (fun _ -> assert false)

      method post_add_hook _ ctrl =
	(* This is run in controller context, right after program startup.
           Register now the lever function, which starts a helper service.
	 *)
        let lever =
          L.register ctrl
	    (fun _ _ -> Netplex_cenv.system_shutdown (); (true)) in
	(* Remember the created lever until the child forks *)
	server_shutdown_lever <- lever;
        
        (* Call C_Daemonize *)
        if !ref_daemonize_args = "" then
          begin
          let param = (Pkcs11.string_to_char_array "") in
          let _ = c_Daemonize param in
          ()
          end
        else
          begin
          let param = (Pkcs11.string_to_char_array !ref_daemonize_args) in
          let _ = c_Daemonize param in
          ()
          end


      method post_start_hook _ =
           (* Make the lever generally available in the child *)
           LV.set "server_shutdown_lever" server_shutdown_lever;
           (* Get the shutdow helper *)
           let shutdown_lever = LV.get "server_shutdown_lever" in
           try Filter_configuration.get_config !filter_config_file_ref
           with  Filter_common.Modules_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: modules parsing error!";
               | Filter_common.Mechanisms_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: mechanisms parsing error!";
               | Filter_common.Labels_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: labels parsing error!";
               | Filter_common.Ids_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: ids parsing error!";
               | Filter_common.P11_functions_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: PKCS#11 functions parsing error!";
               | Filter_common.Enforce_RO_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: RO enforcing option parsing error!";
               | Filter_common.Forbid_admin -> let _ = shutdown_lever "0" in failwith "Filter configuration: forbid admin option parsing error!";
               | Filter_common.Remove_padding_oracles -> let _ = shutdown_lever "0" in failwith "Filter configuration: remove padding oracles option parsing error!";
               | Filter_common.Actions_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: filter actions parsing error!";
               | Filter_common.Config_file_none -> let _ = shutdown_lever "0" in failwith "Filter configuration: no configuration file!";
               | Filter_common.Config_file_wrong_type -> let _ = shutdown_lever "0" in failwith "Filter configuration: critical exception when parsing the configuration file!";
               | _ -> let _ = shutdown_lever "0" in failwith "Filter configuration: unknown critical exception when parsing the configuration file!";

      (*method post_finish_hook _ _ _ = Netlog.logf `Info "post_finish_hook in pid %d" (Unix.getpid());*)

      (* method shutdown () = Netlog.logf `Info "shutdow hook in pid %d" (Unix.getpid()); *)

    end
   )
ELSE
(** Filter hooks that are defined when we use the filter *)
let custom_hooks =
  ( object(_)
      inherit Netplex_kit.empty_processor_hooks()

      val mutable server_shutdown_lever = (fun _ -> assert false)

      method post_add_hook _ ctrl =
	(* This is run in controller context, right after program startup.
           Register now the lever function, which starts a helper service.
	*)
        let lever = 
          L.register ctrl
	    (fun _ _ -> Netplex_cenv.system_shutdown (); (true)) in
	(* Remember the created lever until the child forks *)
	server_shutdown_lever <- lever
        
      method post_start_hook _ =
           (* Make the lever generally available in the child *)
           LV.set "server_shutdown_lever" server_shutdown_lever;
           (* Get the shutdow helper *)
           let shutdown_lever = LV.get "server_shutdown_lever" in
           try Filter_configuration.get_config !filter_config_file_ref
           with  Filter_common.Modules_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: modules parsing error!";
               | Filter_common.Mechanisms_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: mechanisms parsing error!";
               | Filter_common.Labels_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: labels parsing error!";
               | Filter_common.Ids_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: ids parsing error!";
               | Filter_common.P11_functions_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: PKCS#11 functions parsing error!";
               | Filter_common.Enforce_RO_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: RO enforcing option parsing error!";
               | Filter_common.Forbid_admin -> let _ = shutdown_lever "0" in failwith "Filter configuration: forbud admin option parsing error!";
               | Filter_common.Remove_padding_oracles -> let _ = shutdown_lever "0" in failwith "Filter configuration: remove padding oracles option parsing error!";
               | Filter_common.Actions_except -> let _ = shutdown_lever "0" in failwith "Filter configuration: filter actions parsing error!";
               | Filter_common.Config_file_none -> let _ = shutdown_lever "0" in failwith "Filter configuration: no configuration file!";
               | Filter_common.Config_file_wrong_type -> let _ = shutdown_lever "0" in failwith "Filter configuration: critical exception when parsing the configuration file!";
               | _ -> let _ = shutdown_lever "0" in failwith "Filter configuration: unknown critical exception when parsing the configuration file!";

      (* method post_finish_hook _ _ _ = Netlog.logf `Info "post_finish_hook in pid %d" (Unix.getpid()); *)
      (* method shutdown () = Netlog.logf `Info "shutdow hook in pid %d" (Unix.getpid());                *)
      (* method global_exception_handler _ = Netlog.logf `Info "exception handler hook in pid %d" (Unix.getpid()); (true) *)
    end
   )
ENDIF
ELSE

IFDEF DAEMONIZE
THEN
let custom_hooks =
  ( object(self)
      inherit Netplex_kit.empty_processor_hooks()
      method post_add_hook _ _  =
        if !ref_daemonize_args = "" then
          begin
          let param = (Pkcs11.string_to_char_array "") in
          let _ = c_Daemonize param in
          ()
          end
        else
          begin
          let param = (Pkcs11.string_to_char_array !ref_daemonize_args) in
          let _ = c_Daemonize param in
          ()
          end
    end
   )
ELSE
let custom_hooks =
  ( object(self)
      inherit Netplex_kit.empty_processor_hooks()
    end
   )
ENDIF
ENDIF

let rpc_pkcs11_factory = 
  Rpc_netplex.rpc_factory
    ~configure
    ~socket_config
    ~name:"rpc_pkcs11"
    ~setup
    ~hooks:(fun _ -> custom_hooks)
    (* No need for posthooks when there is no filte r*)
    ()

let enable_pkcs_debug () = 
  ref_pkcs_debug := 1;
  ()

let set_daemonize_args s =
  ref_daemonize_args := s;
  ()

let start() =
  (* Set up signal handler for SIGINT *)
  Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ ->
    print_endline "Received SIGINT, shutting down...";
    exit 0));

  let (opt_list, cmdline_cfg) = Netplex_main.args() in

  let opt_list =
    [ "-debug", Arg.String (fun s -> Netlog.Debug.enable_module s),
      "<module>  Enable debug messages for <module>";

      "-debug-all", Arg.Unit (fun () -> Netlog.Debug.enable_all()),
      "  Enable all debug messages";

      "-debug-list", Arg.Unit (fun () -> List.iter print_endline (Netlog.Debug.names());
                                 raise (Failure "Options")),
      "  Show possible modules for -debug, then exit";
      "-debug-pkcs11", Arg.Unit (fun () -> enable_pkcs_debug()), " Enable PKCS#11 functions debug prints";
      "-daemonize-param", Arg.String (fun s -> set_daemonize_args s), " String passed to daemonize code (optional)";
    ] @ opt_list in

  Arg.parse
    opt_list
    (fun s -> raise (Arg.Bad ("Don't know what to do with: " ^ s)))
    "usage: netplex [options]";

  let parallelizer = Netplex_mp.mp() in (* multi-processing *)
  Netplex_main.startup
    parallelizer
    Netplex_log.logger_factories   (* allow all built-in logging styles *)
    Netplex_workload.workload_manager_factories (* ... all ways of workload management *)
    [ rpc_pkcs11_factory ]
    cmdline_cfg


let () =
  Netsys_signal.init();
  start()

