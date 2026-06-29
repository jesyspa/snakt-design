# Sequence approach
With this approach we want to translate the kotlin `intArray` to viper sequences. 
- Viper sequences as well as `intArray`s do have a fixed length.
- Viper sequences are immutable whereas `intArray`s are mutable.

## Connection to Uniqueness System
We treat the whole array as unique or shared. There is not the option that for some part of the array we have access and for others we don't.

If the `intArray` is unique, we want to be able to normally read and write to it.
- intuitively a reading form the array should make it partially moved. When we assign it back, it becomes unique again. 
- This is however very challenging, because tracking all the accesses becomes difficult.
- Since the `intArray` only contains primitive types, we might get away with just always use `unfolding` to access some part of it. 
If the `intArray` is shared, reads are replaced with `havoc` calls and writes are removed completely, or we throw a uniqueness error. 

**For this document we assume that shared read and writes result in a uniqueness error. Hence in the following we will assume that every read and write happens on a unique `intArray`.**

### How to translate
We want to be able to model the situation where the array is changed by another function: 

```kotlin
// foo(@Unique @Borrow arr: IntArray)

val arr = IntArray(5)
foo(arr)
assert(arr[0] == 0) // should fail
```

This example shows that we can not just replace the `IntArray` with a viper Seq. Because then we would pass the viper sequence to the function, which is a immutable. Hence the assertion will be true, even though it should fail (because foo could have changed the `arr[0]`). 

Therefore, we need to be able to hand off permissions to the sequence. 

### Represent the data
We introduce a special field that holds the sequence:
```viper
field data: Seq[Int]

predicate uniqueIntArray(this: Ref) {
	acc(this.data, write)
}
```

With this approach, `foo` will require and ensure the unique predicate and viper can infer, that all the data could have changed. What is special is that the size must remain constant. So `assert(arr.size == 5)` must verify when added after the call to foo. 


### Constructor
The constructor must be augmented with this additional postconditions:
```viper
// unfolding omitted
requires 0 <= par_size
ensures |result.data| == par_size
ensures forall i: Int :: 0 <= i && i < |result.data| ==> result.data[i] == 0
```
This is just to make sure that the initialization is done correctly.

### Property size
If we go with the current standard approach with the properties then the `IntArray.size` property would be translated to a pure viper function. This is the case, because it is immutable and closed. 
This results in the annoying situation where we have two ways to get the size of a `intArray`: One option is to access the data field and take the length of the actual viper sequence (`|intArray.data|`), the other option is to use the property function `getSize(intArray)`. 

One could remove the property function and always use the actual viper sequence to get the length. 
**Advantages**
- removed duplicate information and the need to keep it in sync
**Disadvantages**
- It is no longer possible to get the length of a shared `intArray`

**I believe it is better to use the viper sequence as the source of truth for the length.**
- The keeping in sync is very annoying und adds probably quite some overhead to the viper.
- I think there are very few situations, where one need to access the length of a sequence but never get or sets a value (which would be treated as an uniqueness error). 

### Function: get
For the get function one should add the following contract (additionally to the type information):
```viper
function intArrayGet(intArray: Ref, index: Ref) : Int
  requires uniqueIntArray(intArray)
  requires 0 <= index 
  requires index < unfolding uniqueIntArray(intArray) in |intArray.data|
  ensures uniqueIntArray(intArray)
  ensures old(|intArray.data|) == |intArray.data|            // add unfolding
  ensures forall i: Int :: 
	  0 <= index < |intArray.data| 
	  ==> intArray.data[i] == old(intArray.data[i])          // add unfolding
  ensures result == intArray.data[index]                     // add unfolding
// insert intFromRef(index) where needed
```

It might be more performant to just inline the `intArrayGet` call. Because then viper does not need to perform the book keeping with the `old` as well as does not need to have to track the `forall`. 

The Kotlin code `intArray.get(index)` could just be replaced to `unfolding unique(intArray) in intArray[index]`. 
**I believe the inlining is the better approach, because it removes the need of the forall quantifier and it is closer to the viper implementation (fewer rounds of indirections)**


### Function set
One could also augment the `intArray.set` function with additional pre-postconditions. However a similar problem arises with the `forAll`. It is also possible to inline the set operation:
```kotlin
val intArray[5] = exp
```
Would become in viper:
```viper
unfold uniqueIntArray(intArray)
intArray.data = intArray.data[5 := exp]
fold uniqueIntArray(intArray)
```


### Multiset
To be able to reason about the content of the array for example in a sorting algorithm, we need to be able to express that the elements in the array remain the same. For this we need to be able to transform the `intArray` into a viper multiset. 
For this we need to add the function:

```viper
function seqToMultiset(s: Seq[Int]): Multiset[Int] { 
	|s| == 0 ? Multiset[Int]() : Multiset(s[0]) union seqToMultiset(s[1..]) 
}
```

Furthermore, we need to expose a special function that allows the user to write seqToMultiset in the contract. This can be done by a FullySpecialKotlinFunction that replaces the call to `unfolding(uniqueIntArray(s)) in seqtoMultiset(s.data)`

Some testing has revealed that Viper can not infer that the length of the multiset is the same as of the sequence. Therefore the following axiom should be added:
```viper
axiom {
    (forall r: Seq[Int] ::
      {seqToMultiset(r)}
      |seqToMultiset(r)| == |r|
    )
  }
```



## Implementations
- [ ] If a function takes a `@Unique` and `@Borrowed` `IntArray` as parameter it must ensure that the size remains constant. `old(|arr.data|) == |arr.data|` (unfolding is omitted here)
- [ ] The predicate of `IntArray` must be handled specially because the field `data` does not actually exists in Kotlin.
- [ ] For the `size` property, we must create a `SpecialProperty` with a special accessor. 
- [ ] The functions `get` and `set` must receive their own special case.
- [ ] Add the built-in function `seqToMultiset`

## Challenges
- Getting the types right is not straight forward. We would need to add a Special field, for which it is unclear what the actual type (in the ExpEmbedding world) would be. Because all the types we have there are defined using a domain function, however we basically just want to have it `Seq[Int]`. The current solution would be to create a new type `IntArrayData` that get's mapped to a `Ref` and we add injectivity from it to the `Seq[Int]`. However this results in a unnecessary redirection. But this is a future problem.
- Automated fold+unfolds is also tricky. Because the uniqueness checker does not know that our `data` field exists. Therefore we should use Manual permissions for it. Also at the moment we are not able to write fold and unfolds directly in the program. We should be able to write `unfold(x)` and the program should infer the type of x and select the correct unique predicate.
- An initial test revealed that the verification for this approach is very slow. 



# Domain Approach
This approach is more flexible. It allows to have partial permissions for the array. For this we model the array as multiple domain functions and a field. 
The existing domain would be extended with the following functions:

## Implementation
The actual data is again stored in a field:
```viper
field data : Ref
```

 **slot** the slot function maps an array instance and a index to the corresponding element. The element is also just a `Ref` and not directly a Int, because we want to be able to access the field on it.
 ```viper
 domain rt {
	 function slot(arr: Ref, index: Int) : Ref
 }
 ```

**size** the size of the array must also be stored as a function
 ```viper
 domain rt {
	 function size(arr: Ref) : Int
	 
	 
	 axiom sizeIsNonNeg {
		(forall arr: Ref ::  
		  { size(arr) }  
		  size(arr) >= 0
	 }
 }
 ```

**slotToArray** this function is used for the injectivity. We need to be able to map a slot to the array it belongs to. Furthermore we need **slotToIndex**, which given a slot returns the index of the slot in the array.

```viper

domain rt {
	function slotToArray(slot: Ref) : Ref
	
	function slotToIndex(slot: Ref) : Int
	
	axiom all_diff {
		forall a: Ref, i: Int :: { slot(a,i) }
	      slotToArray(slot(a,i)) == a && slotToIndex(slot(a,i)) == i
  }
}
```

In the predicate of the `IntArray` we need to add the access to all the fields. 
```viper
predicate uniqueIntArray {
	forall j: Int :: (0 <= j && j < size(a)) ==> acc(slot(a,j).data)
}
```

### Constructor
The constructor method needs to be extended with some pre+postconditions. We need to require that the length argument is non negative and we need to ensure the size property is the same as the supplied argument and that the initial values are all zero. 
```viper
requires 0 <= par_size
ensures intToRef(size(arr)) == par_size
ensures unfolding unique(result) in (
	forall i: Int :: 0 <= i && i < size(arr) 
			==> intFromRef(slot(result, i).data) == 0
	)
```

### Property size
The size function can just be a call to the domain function and then translated to our ref type:
```viper
intToRef(size(arr))
```

### Get function
The get function can just be translated to `slot(arr,i).data`. Of course before the necessary unfolds need to be performed (unfolding the unique predicate of `arr`)

### Set function
Similarly to the get function we can translate the set assignment to `slot(arr,i).data = newValue`. For the predicates the same holds.

### Multiset
Similar as before we need a way to translate the structure to a multiset that allows us to reason about permutations.

We first have a function that allows us to reason about part of the array.
```viper
function slotsToMultiset(arr: Ref, start: Int, end: Int): Multiset[Int]
    requires 0 <= start && start <= end && end <= size(arr)
    requires forall j: Int :: { slot(arr, j).array_cell_int } 
        (start <= j && j < end) ==> acc(slot(arr, j).data, write)
    ensures |result| == end - start
{
    start == end ? Multiset[Int]() :
        Multiset(slot(arr, start).array_cell_int) 
	    union 
	    slotsToMultiset(arr, start + 1, end)
}
```
and then we can have a top level wrapper that calculates the multiset of all of the full array

```viper
function arrayToMultiset(arr: Ref): Multiset[Int]
    requires acc(uniqueIntArray(arr), write)
    ensures |result| == size(arr)
{
    unfolding acc(uniqueIntArray(arr), wildcard) in slotsToMultiset(arr, 0, size(arr))
}
```

## Open Questions
- It is not clear what the best approach is for the types of the return type. For example, should the `size` function return a `Int` or a `Ref` ?
- For the permissions the similar problem arises when it comes to automated fold and unfolds. I think currently the best approach is just to always use `unfolding in` for the get method and surround the set function with a `unfold` and `fold`. Then code like this is not possible: `a[i] = a[j]` but for the prototyping requiring that `a[j]` is stored in a temp variable is fine.