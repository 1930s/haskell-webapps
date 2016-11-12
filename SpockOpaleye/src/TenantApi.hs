{-# LANGUAGE Arrows                #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}

module TenantApi
  ( createTenant
  , readTenants
  , readTenantById
  , readTenantByBackofficedomain
  , removeTenant
  , updateTenant
  , activateTenant
  , deactivateTenant
  ) where

import           ApiBase
import           Control.Arrow
import           Control.Lens
import           Control.Monad.Reader
import           Control.Monad.Writer
import           Data.Maybe
import           Data.Text
import           Database.PostgreSQL.Simple (Connection)
import           DataTypes
import           GHC.Int
import           Opaleye
import           OpaleyeDef
import           Prelude                    hiding (id)
import           RoleApi
import           UserApi

createTenant :: Connection -> TenantIncoming -> AuditM Tenant
createTenant conn tenant = do
  createRow conn tenantTable tenant

activateTenant :: Connection -> Tenant -> IO Tenant
activateTenant conn tenant = setTenantStatus conn tenant TenantStatusActive

deactivateTenant :: Connection -> Tenant -> IO Tenant
deactivateTenant conn tenant = setTenantStatus conn tenant TenantStatusInActive

setTenantStatus :: Connection -> Tenant -> TenantStatus -> IO Tenant
setTenantStatus conn tenant st = updateTenant conn (tenant & status .~ st)

updateTenant :: Connection -> Tenant -> IO Tenant
updateTenant conn tenant = do
  updateRow conn tenantTable tenant

removeTenant :: Connection -> Tenant -> IO GHC.Int.Int64
removeTenant conn tenant = do
  tenant_deac <- deactivateTenant conn tenant
  _ <- updateTenant conn (tenant_deac & ownerid .~ Nothing)
  usersForTenant <- readUsersForTenant conn tid
  rolesForTenant <- readRolesForTenant conn tid
  mapM_ (removeRole conn) rolesForTenant
  mapM_ (removeUser conn) usersForTenant
  runDelete conn tenantTable matchFunc
  where
    tid = tenant ^. id
    matchFunc :: TenantTableR -> Column PGBool
    matchFunc tenant'  = (tenant' ^. id) .== (constant tid)

readTenants :: Connection -> IO [Tenant]
readTenants conn = runQuery conn tenantQuery

readTenantById :: Connection -> TenantId -> IO (Maybe Tenant)
readTenantById conn tenantId = do
  listToMaybe <$> (runQuery conn $ (tenantQueryById tenantId))

readTenantByBackofficedomain :: Connection -> Text -> IO (Maybe Tenant)
readTenantByBackofficedomain conn domain = do
  listToMaybe <$> (runQuery conn $ (tenantQueryByBackoffocedomain domain))

tenantQuery :: Opaleye.Query TenantTableR
tenantQuery = queryTable tenantTable

tenantQueryById :: TenantId -> Opaleye.Query TenantTableR
tenantQueryById tId = proc () -> do
  tenant <- tenantQuery -< ()
  restrict -< (tenant ^. id) .== (constant tId)
  returnA -< tenant

tenantQueryByBackoffocedomain :: Text -> Opaleye.Query TenantTableR
tenantQueryByBackoffocedomain domain = proc () -> do
  tenant <- tenantQuery -< ()
  restrict -< (tenant ^. backofficedomain) .== (pgStrictText domain)
  returnA -< tenant
