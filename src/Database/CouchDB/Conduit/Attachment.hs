{-# LANGUAGE OverloadedStrings #-}

-- | CouchDB document attachments.
--
--   /Note about attachment paths:/ Attachments may have embedded @\/@ 
--   characters that are sent unescaped to CouchDB. You can use this to 
--   provide a subtree of attachments under a document. A DocID must have 
--   any @\/@ escaped as @%2F@. So if you have document @a\/b\/c@ with an 
--   attachment @d\/e\/f.txt@, you would be able to access it at 
--   @http:\/\/couchdb\/db\/a%2fb%2fc\/d\/e\/f.txt@. 
--
--   @couchdb-conduit@ automaticaly normalizes attachment paths.

module Database.CouchDB.Conduit.Attachment (
    couchGetAttach,
    couchPutAttach,
    couchDeleteAttach
) where

import Control.Exception.Lifted (throw)

import Data.Maybe (fromMaybe)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 (split)
import qualified Data.Aeson as A
import Data.Conduit (ResumableSource, ($$+-))
import qualified Data.Conduit.Attoparsec as CA

import Network.HTTP.Conduit (RequestBody(..), Response(..))
import qualified Network.HTTP.Types as HT

import Database.CouchDB.Conduit.Internal.Connection 
            (MonadCouch (..), Path, Revision, mkPath)
import Database.CouchDB.Conduit.Internal.Parser (extractRev)
import Database.CouchDB.Conduit.LowLevel (couch, protect')

-- | Get document attachment and @Content-Type@.
couchGetAttach :: MonadCouch m =>
       Path             -- ^ Database
    -> Path             -- ^ Document
    -> ByteString       -- ^ Attachment path
    -> m (ResumableSource m ByteString, ByteString)
couchGetAttach db doc att = do
    Response _ _ hs bsrc <- couch HT.methodGet
            (attachPath db doc att)
            []
            []
            (RequestBodyBS "")
            protect'
    return (bsrc, fromMaybe "" . lookup "Content-Type" $ hs)

-- | Put or update document attachment
couchPutAttach :: MonadCouch m =>
       Path             -- ^ Database
    -> Path             -- ^ Document
    -> ByteString       -- ^ Attachment path
    -> Revision         -- ^ Document revision
    -> ByteString       -- ^ Attacment @Content-Type@
    -> RequestBody m    -- ^ Attachment body
    -> m Revision
couchPutAttach db doc att rev contentType body = do
    Response _ _ _ bsrc <- couch HT.methodPut
            (attachPath db doc att)
            [(HT.hContentType, contentType)]
            [("rev", Just rev)]
            body
            protect'
    j <- bsrc $$+- CA.sinkParser A.json
    either throw return $ extractRev j

-- | Delete document attachment
couchDeleteAttach :: MonadCouch m =>
       Path             -- ^ Database
    -> Path             -- ^ Document
    -> ByteString       -- ^ Attachment path
    -> Revision         -- ^ Document revision
    -> m Revision
couchDeleteAttach = undefined

------------------------------------------------------------------------------
-- Internal
------------------------------------------------------------------------------

-- | Make normalized attachment path
attachPath :: Path -> Path -> ByteString -> Path
attachPath db doc att = 
    mkPath $ db : doc : attP
  where
    attP = split '/' att