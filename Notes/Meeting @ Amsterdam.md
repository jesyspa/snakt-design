- What functionalities we should provide at the beginning for the users.
- What would be interesting to prove for Kotlin programs
- We have to aim "lower" but not that much, we should aim at people with a computer science background.
- Ideally, the tool can give some information without defining a specification of the functionality.
  - If that is not achievable, then the user can specify contracts to Kotlin functions (in an idiomatic way), to ensure the specifications are held.
  - If it is achievable, then we will have more users who will often use the tool.
- Kotlin is also used on the server\-side, so it may be interesting investigating that field.
  - There are also users in the crypto\-currencies field.
- According to Anton, the amount of annotation to specify the code has to be minimal.
  - Anton suggests that we can make Kotlin contracts stronger.
  - Initial prototype will be comment\-oriented, we are just interested in a proof\-of\-concept that the functionalities work.
- Regarding Kotlin Coroutines, there could situation that they can be easy to verify.
  - Coroutine dispatchers are the most hard to verify, it is worth to investigate.
- Anton proposed to investigate **[Refinement Type](<https://en.wikipedia.org/wiki/Refinement_type>)**. We could express a lot of properties with those types. Like, for example, that an integer is in\-bound when used as an array index.
  - The refinement types can be compiled down to pre\-condition and post\-condition.
- Collection chain processing is interest to investigate, like showing the user that a particular operation is not necessary, or to prove something helpful.
  - Checks that an operation can be performed in\-place, without allocating a new collection.
- It may be worth to extend the **Kotlin contracts**. Or work on the Kotlin contracts, to be translated into Viper.
  - We have a lot of code that uses Kotlin contracts already so we could perform testing on them.
    - Anton found at least 10 repositories use Kotlin contracts.
- Going with the existing Kotlin contracts is an interesting idea since we have a potential codebase to do testing.
- Anton suggests the correct usage of API using pre\-conditions and post\-conditions. Specifically, for people using Spring\+Kotlin.
- Regarding Kotlin Multiplatform, it may be interesting to verify the **serialization** part. For the server side, we have **Ktor**.
- For the future, it would be useful the information got by the tool to perform optimizations. 
- We should create a generic schema for the information we infer from our analysis. And, provide this information to the user.
- Collection non\-emptiness check and null\-safety checks.

### **Moving to Viper**
- According to Anton, Viper could be overkilling for our purpose. Because, Viper is more suited for concurrent code.
  - A system like Dafny and Why3 are a better suit for our case, because of the aliasing\-system.  Their theories are simpler.
  - It would make sense translating some Kotlin code to Dafny

### **After the meeting with Marat**
- According to Marat, we choose the right direction to develop MVP for Kotlin contracts converter into Viper.
  - In the future, we are going to tackle coroutines and concurrency.
- In the next week we should understand how the new Kotlin contracts syntax works.
- We have a lot of open questions about converting Kotlin code into Viper.
  - **First**: relationship with class hierarchies.
  - **Second**: memory aliasing.
  - **Third**: how to model first class functions.
- We should discuss with the Viper team about the encoding we are interested in. Probably they solved already some encoding problem.
- In the future, we are going to write the transpiler. We should start by giving a look to *Gobra*, and understand how they approach the “transpilation process”.
  - We should start writing a document for mapping Kotlin types into Viper. This task will be assigned to Anton.
- We may want to speak to *Dmitry Novozhilov* about Kotlin Contracts.















