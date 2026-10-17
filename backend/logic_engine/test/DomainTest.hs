module Main where

import Control.Monad (unless)
import Data.Either (isLeft)
import Data.List (isInfixOf)
import Domain
import DomainLibrary
import Domains.Objects.Definition
import qualified Domains.Objects.Parser as DerivedParser
import qualified Domains.Objects.Evaluation as DerivedEvaluation
import Ontology
import AtomicParser
import AtomicPerformative
import AtomicPropertyCheck
import AtomicPropertyQuery
import AtomicSentence
import AtomicEvaluation
import Layer2Parser
import Layer2Evaluation
import Discourse
import Pretty
import Result

check name condition = unless condition (fail name)
parsed domain = either error id . parseAtomicSentencesWith domain
library domain = DomainLibrary domain
  (DerivedParser.derivedPerformativesWith domain)
  (DerivedParser.derivedQuestionsWith domain)
  (DerivedEvaluation.evaluateDerivedWith domain) (\_ -> holdsProperty) (:[]) id

main = do
  check "existing domain validates" (validateDomain objectsDomain == Right objectsDomain)
  -- Test-only attribute additions exercise the generic engine, not a second domain.
  let marker = AttributeId "marker"
      marked = ValueId "marked"
      unary = AttributeDefinition marker [] [ValueDefinition marked ["flagged"]]
      extended = objectsDomain {domainAttributes = domainAttributes objectsDomain ++ [unary]}
      input = "A1 flagged. A1 blue. A1 marked? marker of A1?"
      (world, feedback) = evaluateAtomicSentencesWith extended (World []) (parsed extended input)
  check "unary definition validates" (validateDomain extended == Right extended)
  object <- case world of World [item] -> pure item; _ -> fail "expected one object"
  check "independent attributes survive assignment"
    (attributeOf marker object == Just marked && attributeOf (AttributeId "color") object == Just (ValueId "blue"))
  check "unary check and query"
    (map (pretty . feedbackAnswer) (drop 2 feedback) == ["true", "marked"])
  let (cleared, _) = evaluateAtomicPerformativeWith extended world
        (RemoveAttribute (AtSquare (0,0)) (RemoveStored marker))
  check "unary absence is false"
    (case evaluateAtomicPropertyCheckWith extended cleared (APC (AtSquare (0,0)) (AttributeValue marker marked)) of Result False -> True; _ -> False)
  check "unary query after removal is absent"
    (case evaluateAtomicPropertyQueryWith extended cleared (APQ (Stored marker) (AtSquare (0,0))) of Result Absent -> True; _ -> False)
  check "foreign vocabulary does not leak into default parser" (isLeft (parseAtomicSentences input))
  let invalid = AttributeValue marker (ValueId "other")
  check "invalid values never create an object"
    (fst (evaluateAtomicPerformativeWith extended (World []) (AP (ById (Id 2)) invalid)) == World [])
  check "invalid values fail questions"
    (case evaluateAtomicPropertyCheckWith extended world (APC (AtSquare (0,0)) invalid) of Message _ -> True; _ -> False)
  check "unknown removal attribute rejected"
    (case snd (evaluateAtomicPerformativeWith objectsDomain world (RemoveAttribute (AtSquare (0,0)) (RemoveStored marker))) of Message _ -> True; _ -> False)
  let duplicate = extended {domainAttributes = domainAttributes extended ++ [unary]}
      collision = objectsDomain {domainAttributes = domainAttributes objectsDomain ++
        [AttributeDefinition marker [] [ValueDefinition marked ["red"]]]}
      reserved = objectsDomain {domainAttributes = domainAttributes objectsDomain ++
        [AttributeDefinition marker [] [ValueDefinition (ValueId "it") []]]}
  check "duplicate attributes rejected" (isLeft (validateDomain duplicate))
  check "ambiguous descriptors rejected" (isLeft (validateDomain collision))
  check "reserved words rejected" (isLeft (validateDomain reserved))
  let wide = extended {boardWidth=10,boardHeight=12}
      sentences = either error id (parseSentencesWith (library wide)
        "J12 marked. The marked is blue. Is the marked blue? Does every marked object have a marker?")
      (updated,ranking,pending,answer) = evaluateEntryIn (library wide) (World []) [] sentences
  check "domain passes through descriptions, discourse and derived evaluation"
    (pending == Nothing && "false" `notIn` answer && "true" `isInfixOf` answer &&
     any (\(_,_,properties) -> AttributeValue marker marked `elem` properties) ranking)
  check "coordinates come from selected domain"
    (case updated of World [item] -> positionOf item == Just (9,11); _ -> False)
  check "core coordinates use selected dimensions"
    (parseAtomicSentenceWith wide "J12 marked." == Right (Performative (AP (AtSquare (9,11)) (AttributeValue marker marked))))
  check "default coordinate grammar preserved" (all (isLeft . parseAtomicSentence) ["A01 red.","A9 red.","I1 red."])
  let noDerived = (library extended) {parseDerivedQuestions=const [],parseDerivedPerformatives=const [],evaluateDerivedSentence = \_ _ _ _ -> Nothing}
  check "library controls derived grammar"
    (isLeft (parseSentenceWith noDerived "#1 at the edge?") &&
     not (isLeft (parseSentenceWith noDerived "#1 marked?")))
  check "domain formatting retains original ordered partial-object display"
    (prettyWorldIn objectsDomain (World [emptyObject (Id 0)]) == "#0: ? ? ? on ?\n")
  putStrLn "All domain generalization checks passed."
  where notIn needle text = not (needle `isInfixOf` text)
