module Mission
  ( initDB
  , progress
  , unlocked
  , teamMissions
  , userMission
  ) where

import ClassyPrelude hiding (map)
import Yesod

import           Control.Monad.Trans.Maybe (MaybeT(..), runMaybeT)
import qualified Data.Bimap as Bimap
import           Data.Bimap (Bimap)
import           Data.List (nub)
import qualified Data.Sequence as Seq
import           Database.Persist.Sql (Entity(..), SqlPersistT)
import qualified Yesod.Auth as Auth

import           Util ((∉), mapFromKeyed)
import qualified Application.App as App
import           Application.App (Handler)
import           Application.Model (Character(..), CharacterId, EntityField(..), Mission(..), Unlocked(..))
import qualified Game.Model.Character as Character
import qualified Game.Characters as Characters
import qualified Mission.Goal as Goal
import           Mission.Goal (Goal)

import qualified Mission.Shippuden

list :: [Goal.Mission]
list = Mission.Shippuden.missions
{-# NOINLINE list #-}

map :: HashMap Text Goal.Mission
map = mapFromKeyed (Goal.character, id) list
{-# NOINLINE map #-}

characterMissions :: Text -> [Goal.Mission]
characterMissions name =
    filter (any (Goal.involves name . Goal.objective) . Goal.goals) list

teamMissions :: [Text] -> [Goal.Mission]
teamMissions names = nub $ characterMissions =<< names

initDB :: ∀ m. MonadIO m => SqlPersistT m (Bimap CharacterId Text)
initDB = do
    chars    <- (entityVal <$>) <$> selectList [] []
    insertMany_ .
        filter (∉ chars) $ Character . Character.format <$> Characters.list
    newChars <- selectList [] []
    return $ makeMap newChars

makeMap :: [Entity Character] -> Bimap CharacterId Text
makeMap chars = Bimap.fromList . mapMaybe maybePair $ chars
  where
    maybePair (Entity charId Character{characterName}) =
        (charId, ) . Character.format <$> Characters.lookupName characterName

unlocked :: Handler (HashSet Text)
unlocked = do
    mwho     <- Auth.maybeAuthId
    case mwho of
        Nothing  -> return mempty
        Just who -> do
            ids     <- getsYesod App.characterIDs
            unlocks <- runDB $ selectList [UnlockedUser ==. who] []
            return $ unlock ids unlocks

unlock :: Bimap CharacterId Text -> [Entity Unlocked] -> HashSet Text
unlock ids unlocks = union (setFromList $ mapMaybe look unlocks) $
                     keysSet Characters.map `difference` keysSet map
  where
    look (Entity _ Unlocked{unlockedCharacter}) =
        Bimap.lookup unlockedCharacter ids

progress :: Text -> Int -> Int -> Handler Bool
progress name i amount = fromMaybe False <$> runMaybeT do
    Just who   <- Auth.maybeAuthId
    mission    <- MaybeT . return $ Goal.goals <$> lookup name map
    let len     = length mission
    guard $ i < len
    ids        <- getsYesod App.characterIDs
    char       <- Bimap.lookupR name ids
    objectives <- lift $ runDB do
        void $ upsert (Mission who char i amount) [MissionProgress +=. amount]
        selectList [MissionUser ==. who, MissionCharacter ==. char] []
    guard $ completed mission objectives
    lift $ runDB do
        void . insertUnique $ Unlocked who char
        deleteWhere [MissionUser ==. who, MissionCharacter ==. char]
    return True

userMission :: Text -> Handler (Maybe (Goal.Mission, Seq Int))
userMission name = runMaybeT do
    Just who   <- Auth.maybeAuthId
    mission    <- MaybeT . return $ lookup name map
    ids        <- getsYesod App.characterIDs
    char       <- Bimap.lookupR name ids
    objectives <- lift . runDB $
                  selectList [MissionUser ==. who, MissionCharacter ==. char] []
    return (mission, setObjectives objectives $ Goal.goals mission)

setObjectives :: [Entity Mission] -> Seq Goal -> Seq Int
setObjectives objectives xs = foldl' f (0 <$ xs) objectives
  where
    f acc (Entity _ x) = Seq.update (missionObjective x) (missionProgress x) acc

completed :: Seq Goal -> [Entity Mission] -> Bool
completed mission objectives = and . zipWith ((<=) . Goal.reach) mission $
                               setObjectives objectives mission
