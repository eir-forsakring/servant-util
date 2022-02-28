{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE CPP #-}

module Servant.Util.Combinators.Filtering.Client () where

import Universum hiding (filter)

import Data.Typeable (cast)
import GHC.TypeLits (KnownSymbol)
import Servant (ToHttpApiData (..), toQueryParam, (:>))
import Servant.Client (HasClient (..))
import Servant.Client.Core.Request (Request, appendToQueryString)

import Servant.Util.Combinators.Filtering.Base
import Servant.Util.Combinators.Filtering.Support ()
import Servant.Util.Common

#if MIN_VERSION_servant(0,19,0)
import Data.ByteString (ByteString)
import Data.ByteString.Builder (toLazyByteString)
import qualified Data.ByteString.Lazy as BL

encodeQueryParam :: ToHttpApiData a => a  -> ByteString
encodeQueryParam = BL.toStrict . toLazyByteString . toEncodedUrlPiece
#endif

-------------------------------------------------------------------------
-- Client
-------------------------------------------------------------------------

-- | For given filter return operation name and encoded value.
typeFilterToReq :: ToHttpApiData a => TypeFilter fk a -> (Text, Text)
typeFilterToReq = \case
    TypeAutoFilter (SomeTypeAutoFilter filter) -> autoFilterEncode filter
    TypeManualFilter val                       -> (DefFilteringCmd, toQueryParam val)

-- | Apply filter to a client request being built.
class SomeFilterToReq params where
    someFilterToReq :: SomeFilter params -> Request -> Request

instance SomeFilterToReq '[] where
    someFilterToReq = error "Something got wrong"

instance ( KnownSymbol name
         , Typeable (fk :: * -> FilterKind *)
         , Typeable a
         , ToHttpApiData a
         , SomeFilterToReq params
         ) =>
         SomeFilterToReq ('TyNamedParam name (fk a) ': params) where
    someFilterToReq SomeFilter{..}
        | symbolValT @name == sfName =
            let filter :: TypeFilter fk a = cast sfFilter ?: error "Failed to cast filter"
#if MIN_VERSION_servant(0,19,0)
                (op, value) = encodeQueryParam <$> typeFilterToReq filter
#else
                (op, value) = typeFilterToReq filter
#endif
                keymod = if op == DefFilteringCmd then "" else "[" <> op <> "]"
                key = sfName <> keymod
            in appendToQueryString key (Just value)
        | otherwise =
            someFilterToReq @params SomeFilter{..}

instance (HasClient m subApi, SomeFilterToReq params) =>
         HasClient m (FilteringParams params :> subApi) where
    type Client m (FilteringParams params :> subApi) =
        FilteringSpec params -> Client m subApi
    clientWithRoute mp _ req (FilteringSpec filters) =
        clientWithRoute mp (Proxy @subApi) (foldr someFilterToReq req filters)
    hoistClientMonad pm _ hst subCli = hoistClientMonad pm (Proxy @subApi) hst . subCli
