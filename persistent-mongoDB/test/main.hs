{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# language RankNTypes #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

import MongoInit

import Database.MongoDB (runCommand1)
import Data.Time
import Data.Int
import Data.Word
import Data.IntMap (IntMap)
import Control.Monad.Trans
import Test.QuickCheck
import qualified Data.Text as T
import qualified Data.ByteString as BS
import Text.Blaze.Html
import Text.Blaze.Html.Renderer.Text

import CustomPersistField

-- These tests are noops with the NoSQL flags set.
--
-- import qualified CompositeTest
-- import qualified CustomPrimaryKeyReferenceTest
-- import qualified InsertDuplicateUpdate
-- import qualified PersistUniqueTest
-- import qualified PrimaryTest
-- import qualified UniqueTest
-- import qualified MigrationColumnLengthTest
-- import qualified EquivalentTypeTest

-- These modules were quite complicated. Instead of fully extracting the
-- relevant common functionality, I just copied and de-CPPed manually.
import qualified EmbedTestMongo

-- These are done.
import qualified CustomPersistFieldTest
import qualified DataTypeTest
import qualified EmbedOrderTest
import qualified EmptyEntityTest
import qualified HtmlTest
import qualified LargeNumberTest
import qualified MaxLenTest
import qualified MigrationOnlyTest
import qualified Recursive
import qualified UpsertTest
import qualified PersistentTest
import qualified RenameTest
import qualified SumTypeTest

type Tuple = (,)

dbNoCleanup :: Action IO () -> Assertion
dbNoCleanup = db' (pure ())

share [mkPersist persistSettings, mkMigrate "htmlMigrate"] [persistLowerCase|
HtmlTable
    html Html
    deriving
|]
mkPersist persistSettings [persistUpperCase|
  BlogPost
    article Markdown
    deriving Show Eq
|]

mkPersist persistSettings [persistUpperCase|
DataTypeTable no-json
    text Text
    textMaxLen Text maxlen=100
    bytes ByteString
    bytesTextTuple (Tuple ByteString Text)
    bytesMaxLen ByteString maxlen=100
    int Int
    intList [Int]
    intMap (IntMap Int)
    double Double
    bool Bool
    day Day
    utc UTCTime
|]

mkPersist persistSettings [persistUpperCase|
Foo sql=foo_embed_order
    bars [Bar]
    deriving Eq Show
Bar sql=bar_embed_order
    b String
    u String
    g String
    deriving Eq Show
|]

instance Arbitrary DataTypeTable where
  arbitrary = DataTypeTable
     <$> arbText                -- text
     <*> (T.take 100 <$> arbText)          -- textManLen
     <*> arbitrary              -- bytes
     <*> liftA2 (,) arbitrary arbText      -- bytesTextTuple
     <*> (BS.take 100 <$> arbitrary)       -- bytesMaxLen
     <*> arbitrary              -- int
     <*> arbitrary              -- intList
     <*> arbitrary              -- intMap
     <*> arbitrary              -- double
     <*> arbitrary              -- bool
     <*> arbitrary              -- day
     <*> (truncateUTCTime   =<< arbitrary) -- utc

mkPersist persistSettings [persistUpperCase|
EmptyEntity
|]

mkPersist persistSettings [persistUpperCase|
  Number
    intx Int
    int32 Int32
    word32 Word32
    int64 Int64
    word64 Word64
    deriving Show Eq
|]

mkPersist persistSettings [persistUpperCase|
  MaxLen
    text1 Text
    text2 Text maxlen=3
    bs1 ByteString
    bs2 ByteString maxlen=3
    str1 String
    str2 String maxlen=3
    MLText1 text1
    MLText2 text2
    MLBs1 bs1
    MLBs2 bs2
    MLStr1 str1
    MLStr2 str2
    deriving Show Eq
|]
main :: IO ()
main = do
  hspec $ afterAll dropDatabase $ do
    xdescribe "This test is failing for Mongo by only embedding the first thing." $ do
        RenameTest.specsWith (db' RenameTest.cleanDB)
    DataTypeTest.specsWith
        dbNoCleanup
        (pure ())
        Nothing
        [ TestFn "Text" dataTypeTableText
        , TestFn "Text" dataTypeTableTextMaxLen
        , TestFn "Bytes" dataTypeTableBytes
        , TestFn "Bytes" dataTypeTableBytesTextTuple
        , TestFn "Bytes" dataTypeTableBytesMaxLen
        , TestFn "Int" dataTypeTableInt
        , TestFn "Int" dataTypeTableIntList
        , TestFn "Int" dataTypeTableIntMap
        , TestFn "Double" dataTypeTableDouble
        , TestFn "Bool" dataTypeTableBool
        , TestFn "Day" dataTypeTableDay
        ]
        []
        dataTypeTableDouble
    HtmlTest.specsWith
        (db' (deleteWhere @_ @_ @HtmlTable []))
        Nothing
        HtmlTable
        htmlTableHtml
    EmbedTestMongo.specs
    EmbedOrderTest.specsWith
        (db' (deleteWhere ([] :: [Filter Foo]) >> deleteWhere ([] :: [Filter Bar])))
        Foo
        Bar
    LargeNumberTest.specsWith
        (db' (deleteWhere ([] :: [Filter Number])))
        Number
    MaxLenTest.specsWith
        dbNoCleanup
        MaxLen
    Recursive.specsWith
        (db' Recursive.cleanup)

    SumTypeTest.specsWith (dbNoCleanup) Nothing
    MigrationOnlyTest.specsWith
        dbNoCleanup
        Nothing
    PersistentTest.specsWith (db' PersistentTest.cleanDB)
    -- TODO: The upsert tests are currently failing. Find out why and fix
    -- them.
    xdescribe "UpsertTest is currently failing for Mongo due to differing behavior" $ do
        UpsertTest.specsWith
            (db' PersistentTest.cleanDB)
            UpsertTest.AssumeNullIsZero
            UpsertTest.UpsertGenerateNewKey
    EmptyEntityTest.specsWith
        (lift . db' (deleteWhere @_ @_ @EmptyEntity []))
        Nothing
        EmptyEntity
    CustomPersistFieldTest.specsWith
        dbNoCleanup
        BlogPost

  where
    dropDatabase () = dbNoCleanup (void (runCommand1 "dropDatabase()"))
