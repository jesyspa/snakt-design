# Formal verification vision

Ilya Chernikov, Komi Golov, 2024-06

Over the last year, we have developed a formal verification compiler plugin for Kotlin.  The plugin converts the FIR representation into the Viper verification language, and uses existing Viper tooling to verify its correctness.  This verification is done using symbolic execution, with the help of an SMT solver, and is suitable for a wide range of properties.

There are two major factors that limit the usefulness of our tool.  Firstly, Kotlin lacks alias control, which makes it difficult to verify programs that use the heap.  Secondly, Kotlin only has a limited number of contracts, meaning there are few properties that we can currently express.

Going forward, we would like to broaden our scope to static analysis in general.  Our tool provides a convenient framework for developing analyses.  Those that prove useful can be productionalised and implemented in the Kotlin compiler.

To address the lack of alias control, we are working on a uniqueness system for Kotlin that will allow users to indicate that a particular reference is not aliased with any other.  We believe this system will be lightweight and will provide benefits that will make it worth including in Kotlin proper.

By focusing our attention on individual analyses, rather than on formal verification in general, we can improve our expressivity by defining program annotations relevant to the analysis in question.

## Objectives and Key Results

* O: Implement alias control in Kotlin
  * KR: Design a uniqueness type system (Francesco)
  * KR: Write a prototype of a type checker (Yifan, Komi)
* O: Explore new static analyses for Kotlin
  * KR: Identify and prototype promising directions (Grigorii, Komi)
* O: Increase academic visibility of Kotlin
  * KR: Publish a paper on our uniqueness (Francesco, Komi)
  * KR: Publish a tool paper on our plugin (Grigorii, Komi)
* O: Develop the prototyping capabilities of our tool
  * KR: Identify and implement missing features (Grigorii)
