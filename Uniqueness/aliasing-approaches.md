# Aliasing approaches table
|                                                | Pros                                                                                                                | Cons                                                                                                                                     | Notes                                                                                                   |
|------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| [AliasJava][1]                                 | \- robust annotation system                                                                                         | \- requires too many annotations, not user friendly                                                                                      |                                                                                                         |
| [Alias Burying][2]                             | \- shared borrowed allowed<br>\- lightweight annotations<br>\- uniqueness invariant is relaxed<br>\- built for java | \- not easy to encode, for now the only idea is to have multiple function instances<br>\- probably will not allow to perform smart casts |                                                                                                         |
| [LATTE][3]                                     | \- lightweight annotations<br>\- easier encoding<br>\- local vars annotations are inferred<br>\- built for java     | \- no shared borrowed                                                                                                                    | provides formal rules for annotations checking/inferring                                                |
| [An Entente Cordiale][4]                       | \- theoretically interesting<br>\- more powerful than AB, LATTE                                                     | \- the logic behind is more difficult to be understood by a user<br>\- not designed for an OO language                                   | probably is not what we are going to do, but it's useful for understanding uniqueness and linear logic. |
| [Capabilities for Uniqueness and Borrowing][5] | \- makes some reasoning about closures                                                                              | \- uses awkward destructive-read functions                                                                                               |                                                                                                         |

[1]: http://www.cs.cmu.edu/~aldrich/papers/oopsla02.pdf

[2]: https://onlinelibrary.wiley.com/doi/abs/10.1002/spe.370

[3]: https://arxiv.org/pdf/2309.05637.pdf

[4]: https://link.springer.com/chapter/10.1007/978-3-030-99336-8_13

[5]: http://lampwww.epfl.ch/~phaller/doc/haller-odersky10-Capabilities_for_uniqueness_and_borrowing.pdf