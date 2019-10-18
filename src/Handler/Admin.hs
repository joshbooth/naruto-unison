{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuasiQuotes           #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeFamilies          #-}

-- | Behind-the-scenes utility pages. Require sufficient 'Core.Field.Privilege'.
-- Privilege levels are handled in "Application.App".
module Handler.Admin (getAdminR, postAdminR) where

import ClassyPrelude
import Yesod

import qualified Yesod.Auth as Auth

import           Application.App (Form, Handler, Route(..))
import qualified Application.App as App
import           Application.Model (News(..))
import           Application.Settings (widgetFile)
import qualified Application.Settings as Settings
import qualified Handler.Play as Play

-- | Behind-the-scenes utilities for admin accounts. Requires authorization.
getAdminR :: Handler Html
getAdminR = do
    app <- getYesod
    (newsForm, enctype) <- generateFormPost =<< getNewsForm
    Play.gameSocket
    defaultLayout do
        $(widgetFile "admin/admin")
        $(widgetFile "admin/sockets")

-- | 'getAdminR' for creating news posts.
postAdminR :: Handler Html
postAdminR = do
    app <- getYesod
    ((result, newsForm), enctype) <- runFormPost =<< getNewsForm
    case result of
        FormSuccess news -> do
            runDB $ insert400_ news
            defaultLayout [whamlet|<p>"News posted"|]
        _             -> defaultLayout [whamlet|<p>"Invalid post"|]
    Play.gameSocket
    defaultLayout do
        $(widgetFile "admin/admin")
        $(widgetFile "admin/sockets")

getNewsForm :: Handler (Form News)
getNewsForm = do
    author <- Auth.requireAuthId
    UTCTime date _ <- liftIO getCurrentTime
    return . renderDivs $ News author date
        <$> areq textField "" Nothing
        <*> (unTextarea <$> areq textareaField "" Nothing)
