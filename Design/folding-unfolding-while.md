## Folding-Unfolding-While


### Assumptions
In the first iteration we make the following simplifying assumptions:
- We only read from datastructures.
- Per iteration, we go at most one level deeper.
- We only consider completely unique datastructures.


### Observations
- We can imagine the datastructures as trees.
- There can be a **constant** number of "runners". Runners are variables that are 
assigned to some nodes of the tree and might go deeper in every loop iteration. 
E.g. for a linked list the ``current`` would be a runner.
- If in the current loop iteration, a runner is moved deeper into the tree, we will call 
this runner active. To refer to the initial runner of a loop iteration, we will call them base runner.
- If the object is borrowed, we need to carry the permissions through the loop.
Meaning after the loop we need to fold everything back until we reach the root.
- We will need to use the magic wand feature from viper. 
- The invariant of the loop must be the magic wand giving us the root of the tree.
As well as the predicates from the runners.
- The magic wand should have the form of the unique predicate.
  - (foreach field: field != null ==> unique(field)) --* unique(root)
- At the end of a loop iteration, we need to update the magic wand. This update 
usually involves the following steps:
  -  Create a new magic wand, equivalent with the one in the invariant.
  -  As the body, 
      - For every active runner, add the necessary fold statements to go back to the base runner.
      - apply the old magic wand (for all active runners use the corresponding base runner). 


  
### Examples



#### Linked List Traversal
Some pre/postconditions as well as invariants were removed for better readability.
````viper
method contains(list: Ref, p$v: Ref)
  returns (ret$0: Ref)
  requires acc(UniqueLinkedList(list), write)
  ensures acc(UniqueLinkedList(list), write)
{
    var current: Ref
    var anon$0: Ref
    var current_old: Ref

    unfold acc(UniqueLinkedList(list), write)
    current := list.bf$head

    // start of preping the loop.
    // runners need to be traded for the root.
    package (current != nullValue() ==> acc(UniqueNode(current), write)) --* acc(UniqueLinkedList(list), write) {
        fold acc(UniqueLinkedList(list), write) 
    }
    
    label lbl$continue$0
    invariant (current != nullValue() ==> acc(UniqueNode(current), write)) --* acc(UniqueLinkedList(list), write)
    invariant (current != nullValue() ==> acc(UniqueNode(current), write))

    anon$0 := sp$notBool(boolToRef(current == nullValue()))
    if (boolFromRef(anon$0)) {
        var anon$1: Ref
        unfold acc(UniqueNode(current), write)
        anon$1 := current.bf$value
        if (intFromRef(anon$1) == intFromRef(p$v)) {
            ret$0 := boolToRef(true)
            // fold here, because current is no longer moved.
            // since we do not have any active runners, no need to update the magic wand.
            fold acc(UniqueNode(current), write)
            goto lbl$ret$0
        }
        // a runner update happens. we need to save the old runner.
        current_old := current
        // current is already unfolded.
        current := current.bf$next
        
        // we have seen a runner update. So we need to update the magic wand.
        package (current != nullValue() ==> acc(UniqueNode(current), write)) --* acc(UniqueLinkedList(list), write) {
            // in this loop iteration we unfolded current_old. So this needs to be reversed.
            fold acc(UniqueNode(current_old), write)
            // apply the old magic want (updated current with current_old)
            apply (current_old != nullValue() ==> acc(UniqueNode(current_old), write)) --* acc(UniqueLinkedList(list), write)
        }
        goto lbl$continue$0
    }
    label lbl$break$0

    ret$0 := boolToRef(false)
    
    goto lbl$ret$0
    label lbl$ret$0
    // after the loop we can get the root back again.
    apply (current != nullValue() ==> acc(UniqueNode(current), write)) --* acc(UniqueLinkedList(list), write)
}
````
