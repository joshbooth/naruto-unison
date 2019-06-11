{-# LANGUAGE TemplateHaskell             #-}
{-# LANGUAGE MultiParamTypeClasses       #-}
{-# LANGUAGE TypeFamilies                #-}
{-# LANGUAGE QuasiQuotes                 #-}
{-# LANGUAGE NoBangPatterns              #-}
{-# OPTIONS_GHC -fno-warn-unused-matches #-}

-- | Interface for the PureScript game client.
module Handler.Site
  ( getChangelogR
  , getHomeR
  ) where

import ClassyPrelude.Yesod
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.List as List

import           Core.App (Handler, Route(..))
import           Core.Util (equaling, shorten)
import           Core.Model (Cite(..), EntityField(..))
import           Core.Settings (widgetFile)
import qualified Model.Character as Character
import           Model.Character (Category(..))
import qualified Model.Skill as Skill
import qualified Characters
import qualified Handler.Forum as Forum

(!) :: Text -> Text -> Html
usr ! l = [shamlet| $newline never
<a .skill data-usr=#{usr}>#{l}|]

data LogType = Added | New | Rework | Change

logLabel :: Bool -> LogType -> Text
logLabel True  Added  = "Character added:"
logLabel False Added  = "Added:"
logLabel True  New    = "New character:"
logLabel False New    = "New:"
logLabel True  Rework = "Character rework:"
logLabel False Rework = "Rework:"
logLabel True  Change = "Character update:"
logLabel False Change = "Update:"

getChangelog :: Bool -> LogType -> Text -> Character.Category -> Html
getChangelog long logType name characterType =
    case lookup tagName Characters.map of
        Nothing -> [shamlet|Error: character #{tagName} not found!|]
        Just char -> [shamlet|
$if not long
  <img data-name=#{tagName} .char.head src="/img/ninja/#{shorten(tagName)}/icon.jpg">
<li>
  #{change logType}
  <a .name data-name=#{tagName}>#{display $ Character.category char}
  <ul>
    $if long
      <img data-name=#{tagName} .char.head src="/img/ninja/#{shorten(tagName)}/icon.jpg">
    $forall skills <- NonEmpty.take 4 $ Character.skills char
      <li>
        $forall skill <- separate skills
          <a .skill data-name=#{tagName}>#{Skill.name skill}
|]
  where
    separate       = List.nubBy (equaling Skill.name) . toList
    tag Original   = name
    tag Reanimated = name ++ " (R)"
    tag Shippuden  = name ++ " (S)"
    tagName       = tag characterType
    change        = logLabel long
    display Original = [shamlet|#{name}|]
    display Reanimated     = [shamlet|#{name}
<a .minor data-name=#{tagName}>ℝ|]
    display Shippuden     = [shamlet|#{name}
<a .minor data-name=#{tagName}>𝕊|]

-- * HANDLERS

-- | Renders the changelog.
getChangelogR :: Handler Html
getChangelogR = defaultLayout do
    setTitle "Naruto Unison: Changelog"
    $(widgetFile "tooltip/tooltip")
    $(widgetFile "changelog/changelog")
  where
    changelog = getChangelog True

-- | Renders the main site.
getHomeR :: Handler Html
getHomeR = do
    topics   <- Forum.selectWithAuthors [] [Desc TopicTime, LimitTo 10]
    citelink <- liftIO Forum.makeCitelink
    defaultLayout do
        setTitle "Naruto Unison"
        $(widgetFile "tooltip/tooltip")
        $(widgetFile "home/home")
  where
    changelog = getChangelog False