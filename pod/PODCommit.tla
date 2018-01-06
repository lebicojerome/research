----------------------------- MODULE PODCommit -----------------------------
(***************************************************************************)
(* This specification is the very basic version of POD (Proof of Devotion) *)
(* from Nebulas. *)
(* In this specification, we have the following assumptions to simplity        *)
(* the basic idea.                                               *)
(*                                                *)
(*  - No dumber node. *)
(*  - No dynasty change. *)
(*  - No node change or abdication. *)
(*  - Assume one node only propose one value. *)
(*  - Assume there is no failure node, and eventually all nodes should be consistent. *)
(*  - We don't consider the liveness problem. *)
(*  - We don't consider normal nodes besides validators. *)
(***************************************************************************)
CONSTANT Validator, \* The set of validators
    Majority \* 1+ n * 2/3 validators

VARIABLES vrState, \* vrState[r] is the state of validator
    vrPrepared, \* vrPrepared[r] is the set of validators from which r has received "Prepared" messages for v's proposal
    vrCommitted, \* vrCommitted[r] is the set of validators from which r has received "vote" messages for v's proposal
    vrFinal, \* vrFinal[r] is the final value, which the proposer.
    msgs
    (***********************************************************************)
    (* In the protocol, processes communicate with one another by sending  *)
    (* messages.  For simplicity, we represent message passing with the    *)
    (* variable msgs whose value is the set of all messages that have been *)
    (* sent.  A message is sent by adding it to the set msgs.  An action   *)
    (* that, in an implementation, would be enabled by the receipt of a    *)
    (* certain message is here enabled by the presence of that message in  *)
    (* msgs.  For simplicity, messages are never removed from msgs.  This  *)
    (* allows a single message to be received by multiple receivers.       *)
    (* Receipt of the same message twice is therefore allowed; but in this *)
    (* particular protocol, that shouldn't be a problem.                   *)
    (***********************************************************************)

ASSUME 
    /\ Majority \subseteq SUBSET Validator
    /\ \A MS1, MS2, MS3 \in Majority : MS1 \cap MS2 \cap MS3 # {}
       (********************************************************************)
       (* All we assume about the set Majority of majorities is that any   *)
       (* three majorities have non-empty intersection, which makes sure Majority is at least 2/3 validators.     *)
       (********************************************************************)
       
Messages ==
  (*************************************************************************)
  
  (* The set of all possible messages.  The ins field indicates the sender. For "propose" *)
  (* message, the "ins" field means she propose a block. Since we do not mind the proposed value, we do not *)
  (* record the proposed value here. The acc field indicates the sender of a message.   *)
  (*************************************************************************)
  [type : {"propose"}, ins : Validator, acc: Validator] 
      \cup
  [type : {"prepare"}, ins : Validator, acc : Validator] 
      \cup
  [type : {"vote"}, ins : Validator, acc: Validator]
  
PODTypeOK == 
    /\ vrState \in [Validator -> {"working", "prepared", "committed", "finality"}]
     /\ vrFinal \in [Validator -> Validator \cup {"none"}] 
    /\ msgs \subseteq Messages
    
PODInit == \* The initial predicate
    /\ vrState = [v \in Validator |-> "working"]
    /\ vrPrepared = [v \in Validator |-> {}]
    /\ vrCommitted = [v \in Validator |-> {}]
    /\ vrFinal = [v \in Validator |-> "none"]
    /\ msgs = {}
    

-----------------------------------------------------------------------------
(***************************************************************************)
(*                                THE ACTIONS                              *)
(***************************************************************************)
Send(m) == msgs' = msgs \cup {m}
  (*************************************************************************)
  (* An action expression that describes the sending of message m.         *)
  (*************************************************************************)

PreparedSet(set, r) == {m \in set : m.acc = r}
CommittedSet(set, r) == {m \in set : m.acc = r}
-----------------------------------------------------------------------------
(***************************************************************************)
(*                               Validator ACTIONS                         *)
(***************************************************************************)
ValidatorPropose(r) ==
    (***********************************************************************)
    (* Validator try to propose a block                                    *)
    (***********************************************************************)
    /\ vrState[r] = "working"
    /\ vrState' = [vrState EXCEPT![r] = "prepared"]
    /\ vrPrepared' = [vrPrepared EXCEPT![r] = {[type |-> "prepare", ins |->r , acc |-> r]} ]
    /\ msgs' = msgs \cup {[type |-> "propose", ins |->r, acc |-> r],[type |-> "prepare", ins |->r, acc |-> r] }
    /\ UNCHANGED << vrCommitted, vrFinal >>

ValidatorChooseToCommit == 
    (***********************************************************************)
    (* Validator try to vote a block                                       *)
    (***********************************************************************)
    /\ LET ChooseToCommit(r, v) ==
            /\ LET Prepared == {m.ins: m \in PreparedSet(vrPrepared[r], v)}
               IN Prepared \in Majority
            /\ vrState[r] = "prepared"
            /\ vrState' = [vrState EXCEPT ![r] = "committed"]
            /\ vrCommitted' = [vrCommitted EXCEPT ![r]=vrCommitted[r] \cup {[type |-> "vote", ins |-> r, acc |-> v]}]
            /\ Send([type |-> "vote", ins |-> r, acc |-> v])
       IN 
           \A r \in Validator, v \in Validator : ChooseToCommit(r, v)
    /\ UNCHANGED << vrPrepared, vrFinal >>
       
ValidatorChooseToFinal == 
    (***********************************************************************)
    (* Validator try to final a block.                                       *)
    (***********************************************************************)
    /\ LET ChooseToFinal(r, v) ==
            /\ LET Committed == {m.ins: m \in CommittedSet(vrCommitted[r], v)}
               IN Committed \in Majority
            /\ vrState[r] = "committed"
            /\ vrState' = [vrState EXCEPT ![r] = "finality"]
            /\ vrFinal' = [vrFinal EXCEPT ![r] = v ]
       IN 
           \A r \in Validator, v \in Validator : ChooseToFinal(r, v)
    /\ UNCHANGED << vrPrepared, vrCommitted, msgs >>
    
-----------------------------------------------------------------------------
(***************************************************************************)
(*                               RECV messages                         *)
(***************************************************************************)
RecvPropose(r, v) == 
     (***********************************************************************)
    (* The action when recv a prepare message.                              *)
    (***********************************************************************)
    /\ vrState[r] = "working"
    /\ \E m \in msgs :
        /\ m.type = "propose"
        /\ m.ins = v
    /\ vrState' = [vrState EXCEPT ![r] = "prepared"]
    /\ Send([type |-> "prepare", ins |-> r, acc |-> v])
    /\ vrPrepared' = [vrPrepared EXCEPT![r] = {[type |-> "prepare", ins |-> r, acc |-> v]} ]
    /\ UNCHANGED << vrCommitted, vrFinal >>
        
RecvPrepare(r, from, v) == 
    (***********************************************************************)
    (* The action when recv a prepare message.                             *)
    (***********************************************************************)
    /\ vrState[r] = "prepared"
    /\ \E m \in msgs :
        /\ m.type = "prepare"
        /\ m.acc = v
        /\ m.ins = from
    /\ vrPrepared' = [vrPrepared EXCEPT![r] = vrPrepared[r] \cup {[type |-> "prepare", ins |-> r, acc |-> v]} ]
    /\ UNCHANGED <<vrCommitted, vrState, vrFinal, msgs >>
    
RecvVote(r, from, v) == 
    (***********************************************************************)
    (* The action when recv a vote message.                              *)
    (***********************************************************************)
    /\ vrState[r] = "prepared"
    /\ \E m \in msgs :
        /\ m.type = "vote"
        /\ m.acc = v
        /\ m.ins = from
    /\ vrCommitted' = [vrCommitted EXCEPT![r] = vrCommitted[r] \cup {[type |-> "vote", ins |-> r, acc |-> v]} ]
    /\ UNCHANGED <<vrPrepared, vrState, msgs >>
    
-----------------------------------------------------------------------------
PODNext ==
     \/ \E r \in Validator : ValidatorPropose(r)
     \/ \E r, v \in Validator: RecvPropose(r, v) 
     \/ ValidatorChooseToCommit  
     \/ ValidatorChooseToFinal   
     \/ \E r, from, v \in Validator: \/ RecvPrepare(r, from, v)  
                                     \/ RecvVote(r, from, v)  
                                    
\* -----------------------------------------------------------------------------
(*PODConsistent ==  *)
  (*************************************************************************)
  (* A state predicate asserting that two Validators have not arrived at   *)
  (* conflicting decisions.  It is an invariant of the specification.      *)
  (* Actually, PoD don't need this, so no consistency requirement. *)
  (*************************************************************************)
  (* /\ \A r1, r2 \in Validator : ~ /\ vrState[r1] = "aborted"  *)
  (*                     /\ vrState[r2] = "finality"  *)
  (* /\ LET FinalValidators == {r \in Validator:  *)
  (*                                      vrState[r] = "finality"}  *)
  (*   IN \A r1, r2 \in FinalValidators:     *)
  (*                     vrFinal[r1] = vrFinal[r2]  *)
                       
                       
-----------------------------------------------------------------------------
PODSpec == PODInit /\ [][PODNext]_<<vrState, vrPrepared, vrCommitted, vrFinal>>

\* THEOREM PODSpec => [] (PODTypeOK /\ PODConsistent)
=============================================================================
\* Modification History
\* Last modified Sat Jan 06 21:48:30 CST 2018 by xuepeng
\* Created Wed Jan 03 23:52:11 CST 2018 by xuepeng
