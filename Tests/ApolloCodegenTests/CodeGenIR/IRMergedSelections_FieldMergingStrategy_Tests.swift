import XCTest
import Nimble
import OrderedCollections
import GraphQLCompiler
@testable import IR
@testable import ApolloCodegenLib
import ApolloInternalTestHelpers
import ApolloCodegenInternalTestHelpers
import ApolloAPI

class IRMergedSelections_FieldMergingStrategy_Tests: XCTestCase {

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilderTestWrapper!
  var operation: CompilationResult.OperationDefinition!
  var rootField: IRTestWrapper<IR.Field>!

  var schema: IR.Schema { ir.schema }

  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    operation = nil
    rootField = nil
    super.tearDown()
  }

  // MARK: - Helpers

  func buildRootField(
    mergingStrategy: IR.MergedSelections.MergingStrategy
  ) async throws {
    ir = try await IRBuilderTestWrapper(.mock(schema: schemaSDL, document: document))
    operation = try XCTUnwrap(ir.compilationResult.operations.first)

    rootField = await ir.build(
      operation: operation,
      mergingStrategy: mergingStrategy
    ).rootField
  }

  // MARK: - Test MergingStrategy: Ancestors

  func test__mergingStrategy_ancestors__givenFieldInAncestor_includesField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        species
        ... on Pet {
          petName
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asPet = rootField[field: "allAnimals"]?[as: "Pet"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[interface: "Pet"]),
      directSelections: [
        .field("petName", type: .scalar(Scalar_String))
      ],
      mergedSelections: [
        .field("species", type: .scalar(Scalar_String))
      ],
      mergedSources: [
        try .mock(rootField[field:"allAnimals"])
      ],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asPet).to(shallowlyMatch(expected))
  }

  func test__mergingStrategy_ancestors__givenFieldInSiblingInlineFragmentThatMatchesType_doesNotIncludeField() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String
    }

    interface Pet implements Animal {
      species: String
      petName: String
    }

    type Dog implements Animal & Pet {
      species: String
      petName: String
    }
    """

    document = """
    query Test {
      allAnimals {
        ... on Dog {
          species
        }
        ... on Pet {
          petName
        }
      }
    }
    """
    let mergingStrategy: MergedSelections.MergingStrategy = .ancestors

    try await buildRootField(mergingStrategy: mergingStrategy)

    let Scalar_String = try unwrap(self.schema[scalar: "String"])

    // when
    let AllAnimals_asDog = rootField[field: "allAnimals"]?[as: "Dog"]

    let expected = SelectionSetMatcher(
      parentType: try unwrap(self.schema[object: "Dog"]),
      directSelections: [
        .field("species", type: .scalar(Scalar_String))
      ],
      mergedSelections: [],
      mergedSources: [],
      mergingStrategy: mergingStrategy
    )

    // then
    expect(AllAnimals_asDog).to(shallowlyMatch(expected))
  }
}
