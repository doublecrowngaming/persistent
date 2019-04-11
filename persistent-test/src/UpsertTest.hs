{-# OPTIONS_GHC -fno-warn-unused-binds -fno-warn-orphans #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE UndecidableInstances #-} -- FIXME
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

module UpsertTest where

import Init

import Data.Function (on)
import Test.Hspec.Expectations ()

import PersistentTestModels

-- | MongoDB assumes that a @NULL@ value in the database is some "empty"
-- value. So a query that does @+ 2@ to a @NULL@ value results in @2@. SQL
-- databases instead "annihilate" with null, so @NULL + 2 = NULL@.
data BackendNullUpdateBehavior
    = AssumeNullIsZero
    | Don'tUpdateNull

-- | @UPSERT@ on SQL databses does an "update-or-insert," which preserves
-- all prior values, including keys. MongoDB does not preserve the
-- identifier, so the entity key changes on an upsert.
data BackendUpsertKeyBehavior
    = UpsertGenerateNewKey
    | UpsertPreserveOldKey

specsWith
    :: forall backend m. Runner backend m
    => RunDb backend m
    -> BackendNullUpdateBehavior
    -> BackendUpsertKeyBehavior
    -> Spec
specsWith runDb handleNull handleKey = describe "UpsertTests" $ do
  let
    ifKeyIsPreserved expectation =
      case handleKey of
        UpsertGenerateNewKey -> pure ()
        UpsertPreserveOldKey -> expectation

  describe "upsert" $ do
    it "adds a new row with no updates" $ runDb $ do
        Entity _ u <- upsert (Upsert "a" "new" "" 2) [UpsertAttr =. "update"]
        c <- count ([] :: [Filter (UpsertGeneric backend)])
        c @== 1
        upsertAttr u @== "new"
    it "keeps the existing row" $ runDb $ do
        Entity k0 initial <- insertEntity (Upsert "a" "initial" "" 1)
        Entity k1 update' <- upsert (Upsert "a" "update" "" 2) []
        update' @== initial
        ifKeyIsPreserved $ k0 @== k1
    it "updates an existing row - assignment" $ runDb $ do
-- #ifdef WITH_MONGODB
--         initial <- insertEntity (Upsert "cow" "initial" "extra" 1)
--         update' <-
--             upsert (Upsert "cow" "wow" "such unused" 2) [UpsertAttr =. "update"]
--         ((==@) `on` entityKey) initial update'
--         upsertAttr (entityVal update') @== "update"
--         upsertExtra (entityVal update') @== "extra"
-- #else
        initial <- insertEntity (Upsert "a" "initial" "extra" 1)
        update' <-
            upsert (Upsert "a" "wow" "such unused" 2) [UpsertAttr =. "update"]
        ifKeyIsPreserved $ ((==@) `on` entityKey) initial update'
        upsertAttr (entityVal update') @== "update"
        upsertExtra (entityVal update') @== "extra"
-- #endif
    it "updates existing row - addition " $ runDb $ do
-- #ifdef WITH_MONGODB
--         initial <- insertEntity (Upsert "a1" "initial" "extra" 2)
--         update' <-
--             upsert (Upsert "a1" "wow" "such unused" 2) [UpsertAge +=. 3]
--         ((==@) `on` entityKey) initial update'
--         upsertAge (entityVal update') @== 5
--         upsertExtra (entityVal update') @== "extra"
-- #else
        initial <- insertEntity (Upsert "a" "initial" "extra" 2)
        update' <-
            upsert (Upsert "a" "wow" "such unused" 2) [UpsertAge +=. 3]
        ifKeyIsPreserved $ ((==@) `on` entityKey) initial update'
        upsertAge (entityVal update') @== 5
        upsertExtra (entityVal update') @== "extra"
-- #endif

  describe "upsertBy" $ do
    let uniqueEmail = UniqueUpsertBy "a"
        uniqueCity = UniqueUpsertByCity "Boston"
    it "adds a new row with no updates" $ runDb $ do
        Entity _ u <-
            upsertBy
                uniqueEmail
                (UpsertBy "a" "Boston" "new")
                [UpsertByAttr =. "update"]
        c <- count ([] :: [Filter (UpsertByGeneric backend)])
        c @== 1
        upsertByAttr u @== "new"
    it "keeps the existing row" $ runDb $ do
        Entity k0 initial <- insertEntity (UpsertBy "a" "Boston" "initial")
        Entity k1 update' <- upsertBy uniqueEmail (UpsertBy "a" "Boston" "update") []
        update' @== initial
        ifKeyIsPreserved $ k0 @== k1
    it "updates an existing row" $ runDb $ do
-- #ifdef WITH_MONGODB
--         initial <- insertEntity (UpsertBy "ko" "Kumbakonam" "initial")
--         update' <-
--             upsertBy
--                 (UniqueUpsertBy "ko")
--                 (UpsertBy "ko" "Bangalore" "such unused")
--                 [UpsertByAttr =. "update"]
--         ((==@) `on` entityKey) initial update'
--         upsertByAttr (entityVal update') @== "update"
--         upsertByCity (entityVal update') @== "Kumbakonam"
-- #else
        initial <- insertEntity (UpsertBy "a" "Boston" "initial")
        update' <-
            upsertBy
                uniqueEmail
                (UpsertBy "a" "wow" "such unused")
                [UpsertByAttr =. "update"]
        ifKeyIsPreserved $ ((==@) `on` entityKey) initial update'
        upsertByAttr (entityVal update') @== "update"
        upsertByCity (entityVal update') @== "Boston"
-- #endif
    it "updates by the appropriate constraint" $ runDb $ do
        initBoston <- insertEntity (UpsertBy "bos" "Boston" "bos init")
        initKrum <- insertEntity (UpsertBy "krum" "Krum" "krum init")
        updBoston <-
            upsertBy
                (UniqueUpsertBy "bos")
                (UpsertBy "bos" "Krum" "unused")
                [UpsertByAttr =. "bos update"]
        updKrum <-
            upsertBy
                (UniqueUpsertByCity "Krum")
                (UpsertBy "bos" "Krum" "unused")
                [UpsertByAttr =. "krum update"]
        ifKeyIsPreserved $ ((==@) `on` entityKey) initBoston updBoston
        ifKeyIsPreserved $ ((==@) `on` entityKey) initKrum updKrum
        entityVal updBoston @== UpsertBy "bos" "Boston" "bos update"
        entityVal updKrum @== UpsertBy "krum" "Krum" "krum update"

  it "maybe update" $ runDb $ do
      let noAge = PersonMaybeAge "Michael" Nothing
      keyNoAge <- insert noAge
      noAge2 <- updateGet keyNoAge [PersonMaybeAgeAge +=. Just 2]
      -- the correct answer depends on the backend. MongoDB assumes
      -- a 'Nothing' value is 0, and does @0 + 2@ for @Just 2@. In a SQL
      -- database, @NULL@ annihilates, so @NULL + 2 = NULL@.
      personMaybeAgeAge noAge2 @== case handleNull of
          AssumeNullIsZero ->
              Just 2
          Don'tUpdateNull ->
              Nothing
