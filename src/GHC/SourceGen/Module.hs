{-# LANGUAGE CPP #-}
-- Copyright 2019 Google LLC
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE file or at
-- https://developers.google.com/open-source/licenses/bsd

-- | This module provides combinators for constructing Haskell modules,
-- including import and export statements.
module GHC.SourceGen.Module
    ( -- * HsModule'
      HsModule'
    , module'
      -- * Import declarations
    , ImportDecl'
    , qualified'
    , as'
    , import'
    , exposing
    , hiding
    , source
      -- * Imported/exported things
    , IE'
    , thingAll
    , thingWith
    , moduleContents
    )  where

import GHC.Hs.ImpExp (LIEWrappedName, IEWildcard(..), IEWrappedName(..), IE(..))
import GHC.Hs
    ( HsModule(..)
    , ImportDecl(..)
#if MIN_VERSION_ghc(8,10,0)
    , ImportDeclQualifiedStyle(..)
#endif
#if MIN_VERSION_ghc(9,2,0)
    , EpAnn(..)
#endif
    )
#if MIN_VERSION_ghc(9,0,0)
import GHC.Types.SrcLoc (LayoutInfo(..))
import GHC.Unit.Module (IsBootInterface(..))
import GHC.Types.Name.Reader (RdrName)
#else
import RdrName (RdrName)
#endif
#if MIN_VERSION_ghc(9,4,0)
import GHC.Types.PkgQual (RawPkgQual(..))
#endif

import GHC.SourceGen.Syntax.Internal
import GHC.SourceGen.Name
import GHC.SourceGen.Name.Internal
import GHC.SourceGen.Lit.Internal (noSourceText)

module'
    :: Maybe ModuleNameStr
    -> Maybe [IE'] -- ^ Exports
    -> [ImportDecl']
    -> [HsDecl']
    -> HsModule'
module' name exports imports decls = HsModule
    { hsmodName = fmap (mkLocated . unModuleNameStr) name
    , hsmodExports = fmap (mkLocated . map mkLocated) exports
    , hsmodImports = map mkLocated imports
    , hsmodDecls = fmap mkLocated decls
    , hsmodDeprecMessage = Nothing
    , hsmodHaddockModHeader = Nothing
#if MIN_VERSION_ghc(9,0,0)
    , hsmodLayout = NoLayoutInfo
#endif
#if MIN_VERSION_ghc(9,2,0)
    , hsmodAnn = EpAnnNotUsed
#endif
    }

qualified' :: ImportDecl' -> ImportDecl'
qualified' d = d { ideclQualified =
#if MIN_VERSION_ghc(8,10,0)
    QualifiedPre
#else
    True
#endif
}

as' :: ImportDecl' -> ModuleNameStr -> ImportDecl'
as' d m = d { ideclAs = Just (mkLocated $ unModuleNameStr m) }

import' :: ModuleNameStr -> ImportDecl'
import' m = noSourceText (withEpAnnNotUsed ImportDecl)
            (mkLocated $ unModuleNameStr m)
#if MIN_VERSION_ghc(9,4,0)
            NoRawPkgQual
#else
            Nothing 
#endif
#if MIN_VERSION_ghc(9,0,0)
            NotBoot
#else
            False
#endif
            False
#if MIN_VERSION_ghc(8,10,0)
            NotQualified
#else
            False
#endif
            False Nothing Nothing

exposing :: ImportDecl' -> [IE'] -> ImportDecl'
exposing d ies = d
    { ideclHiding = Just (False, mkLocated $ map mkLocated ies) }

hiding :: ImportDecl' -> [IE'] -> ImportDecl'
hiding d ies = d
    { ideclHiding = Just (True, mkLocated $ map mkLocated ies) }

-- | Adds the @{-# SOURCE #-}@ pragma to an import.
source :: ImportDecl' -> ImportDecl'
source d = d { ideclSource =
#if MIN_VERSION_ghc(9,0,0)
    IsBoot
#else
    True
#endif
}

-- | Exports all methods and/or constructors.
--
-- > A(..)
-- > =====
-- > thingAll "A"
thingAll :: RdrNameStr -> IE'
thingAll = withEpAnnNotUsed IEThingAll . wrappedName

-- | Exports specific methods and/or constructors.
--
-- > A(b, C)
-- > =====
-- > thingWith "A" ["b", "C"]
thingWith :: RdrNameStr -> [OccNameStr] -> IE'
thingWith n cs = withEpAnnNotUsed IEThingWith (wrappedName n) NoIEWildcard
                    (map (wrappedName . unqual) cs)
#if !MIN_VERSION_ghc(9,2,0)
                    -- The parsing step leaves the list of fields empty
                    -- and lumps them all together with the above list of
                    -- constructors.
                    []
#endif

-- TODO: support "mixed" syntax with both ".." and explicit names.

wrappedName :: RdrNameStr -> LIEWrappedName RdrName
wrappedName = mkLocated . IEName . exportRdrName

-- | Exports an entire module.
--
-- Note: this is not valid inside of an import list.
--
-- > module M
-- > =====
-- > moduleContents "M"
moduleContents :: ModuleNameStr -> IE'
moduleContents = withEpAnnNotUsed IEModuleContents . mkLocated . unModuleNameStr
