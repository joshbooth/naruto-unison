-- | Handles API routes and WebSockets related to gameplay.
module Handler.Play
    ( gameSocket
    , getPracticeActR, getPracticeQueueR, getPracticeWaitR
    ) where

import ClassyPrelude hiding (Handler)
import Yesod

import           Control.Monad.Loops (untilJust)
import qualified Data.Aeson.Encoding as Encoding
import qualified Data.Cache as Cache
import           Data.Ix (inRange)
import           Data.HashMap.Strict ((!))
import           Data.List (transpose)
import qualified Data.Text as Text
import qualified Database.Persist.Postgresql as Sql
import qualified System.Random.MWC as Random
import qualified Yesod.Auth as Auth
import qualified Yesod.WebSockets as WebSockets
import           Yesod.WebSockets (WebSocketsT)

import qualified Class.Play as P
import           Class.Play (MonadGame)
import           Class.Random (MonadRandom)
import qualified Core.App as App
import           Core.App (Handler)
import           Core.Util (duplic)
import           Core.Fields (Privilege(..))
import qualified Core.Message as Message
import           Core.Model (EntityField(..), User(..))
import qualified Model.Act as Act
import           Model.Act (Act)
import qualified Model.Chakra as Chakra
import           Model.Chakra (Chakras)
import           Model.Character (Character)
import qualified Model.Game as Game
import           Model.Game (Game)
import qualified Model.GameInfo as GameInfo
import qualified Model.Player as Player
import           Model.Player (Player)
import qualified Model.Slot as Slot
import qualified Engine.Chakras as Chakras
import qualified Engine.Turn as Turn
import qualified Characters

-- | 'concat' . 'transpose'
vs :: ∀ a. [a] -> [a] -> [a]
x `vs` y = concat $ transpose [x, y]

bot :: User
bot = User { userIdent      = ""
           , userPassword   = Nothing
           , userName       = "Bot"
           , userAvatar     = "/img/icon/bot.jpg"
           , userVerkey     = Nothing
           , userVerified   = True
           , userPrivilege  = Normal
           , userBackground = Nothing
           , userXp         = 0
           , userWins       = 0
           , userLosses     = 0
           , userStreak     = 0
           , userClan       = Nothing
           , userTeam       = Nothing
           , userMuted      = False
           , userCondense   = False
           }

-- * HANDLERS

-- | Joins the practice-match queue with a given team. Requires authentication.
getPracticeQueueR :: [Text] -> Handler Value
getPracticeQueueR team
  | null (drop 2 team) || not (null (drop 3 team)) =
        invalidArgs ["Wrong number of characters"]
  | any (not . (`member` Characters.map)) team =
        invalidArgs ["Unknown character(s)"]
  | otherwise = do
      (who, _) <- Auth.requireAuthPair
      runDB $ update who [UserTeam =. Just (reverse team)]
      random   <- liftIO Random.createSystemRandom
      gameRef  <- newIORef $ Game.new ns
      runReaderT (runReaderT Chakras.gain gameRef) random
      game     <- readIORef gameRef
      practice <- getsYesod App.practice
      liftIO do
          Cache.purgeExpired practice -- TODO: Move to a recurring timer?
          Cache.insert practice who game
      returnJson GameInfo.GameInfo { vsWho  = who
                                   , vsUser = bot
                                   , player = Player.A
                                   , game   = game
                                   }
  where
    oppTeam = ["Naruto Uzumaki", "Tenten", "Sakura Haruno"]
    ns      = map (Characters.map !) $ team `vs` oppTeam

-- | Wrapper for 'getPracticeActR' with no actions.
getPracticeWaitR :: Chakras -> Chakras -> Handler Value
getPracticeWaitR actChakra xChakra = getPracticeActR actChakra xChakra []

-- | Handles a turn for a practice game. Practice games are not limited by time
-- and use GET requests instead of WebSockets.
getPracticeActR :: Chakras -> Chakras -> [Act] -> Handler Value
getPracticeActR actChakra exchangeChakra actions = do
    (who, _) <- Auth.requireAuthPair -- !FAILS!
    practice <- getsYesod App.practice
    mGame    <- liftIO $ Cache.lookup practice who -- !FAILS
    case mGame of
        Nothing   -> notFound
        Just game -> do
          random  <- liftIO Random.createSystemRandom
          gameRef <- newIORef game
          runReaderT (runReaderT (enactPractice who practice) gameRef) random
  where
    enactPractice who practice = do
        res <- enact actChakra exchangeChakra actions
        case res of
          Left errorMsg -> invalidArgs [errorMsg] -- !FAILS!
          Right ()      -> do
              game'A <- P.game
              P.modify \g -> g
                  { Game.chakra  = (fst $ Game.chakra g, 100)
                  , Game.playing = Player.B
                  }
              Turn.run [] -- TODO
              game'B <- P.game
              liftIO if (null $ Game.victor game'B) then
                  Cache.insert practice who game'B
              else
                  Cache.delete practice who
              lift . returnJson $
                  GameInfo.censor Player.A <$> [game'A, game'B]

formTeam :: [Text] -> Maybe [Character]
formTeam team@[a, b, c]
  | duplic team = Nothing
  | otherwise   = [[a', b', c'] | a' <- lookup a Characters.map
                                , b' <- lookup b Characters.map
                                , c' <- lookup c Characters.map
                                ]
formTeam _ = Nothing

formEnact :: [Text] -> Maybe (Chakras, Chakras, [Act])
formEnact (_:_: _:_:_:_:_) = Nothing -- No more than 3 actions!
formEnact (actChakra:exchangeChakra:acts) = do
    actChakra'      <- fromPathPiece actChakra
    exchangeChakra' <- fromPathPiece exchangeChakra
    acts'           <- traverse fromPathPiece acts
    return (actChakra', exchangeChakra', acts')
formEnact _ = Nothing -- willywonka.gif

sendJson :: ∀ a. ToJSON a => a -> WebSocketsT Handler ()
sendJson = WebSockets.sendTextData .
           Encoding.encodingToLazyByteString . toEncoding

-- | Sends messages through 'TChan's in 'App.App'.
gameSocket :: WebSocketsT Handler ()
gameSocket = do
    app         <- getYesod
    (who, user) <- Auth.requireAuthPair
    teamNames   <- Text.split (=='/') <$> WebSockets.receiveData

    case formTeam teamNames of
      Nothing   -> WebSockets.sendTextData ("Invalid team" :: ByteString)
      Just team -> do
        flip Sql.runSqlPool (App.connPool app) $
            update who [UserTeam =. Just (reverse teamNames)]
        random     <- liftIO Random.createSystemRandom
        randPlayer <- (Player.from :: Bool -> Player) <$>
                      liftIO (Random.uniform random)
        flip runReaderT random do
              let writeQueueChan = App.queue app
              readQueueChan <- (liftIO . atomically) do
                  writeTChan writeQueueChan $ Message.Announce who user team
                  dupTChan writeQueueChan
              (info, writer, reader) <- untilJust do
                msg <- liftIO . atomically $ readTChan readQueueChan
                case msg of
                  Message.Respond mWho writer reader info
                    | mWho == who -> return $ Just (info, writer, reader)
                  Message.Announce vsWho vsUser vsTeam -> do
                      (gameRef :: IORef Game) <- newIORef $ Game.new
                          case randPlayer of
                              Player.A -> team `vs` vsTeam
                              Player.B -> vsTeam `vs` team
                      runReaderT Chakras.gain gameRef
                      game <- readIORef gameRef
                      liftIO $ atomically do
                          writer <- newTChan
                          reader <- newTChan
                          writeTChan writeQueueChan $
                              Message.Respond vsWho reader writer
                              GameInfo.GameInfo
                                  { GameInfo.vsWho  = who
                                  , GameInfo.vsUser = user
                                  , GameInfo.player = Player.opponent randPlayer
                                  , GameInfo.game   = game
                                  }
                          let info = GameInfo.GameInfo
                                  { GameInfo.vsWho = vsWho
                                  , GameInfo.vsUser = vsUser
                                  , GameInfo.player = randPlayer
                                  , GameInfo.game   = game
                                  }
                          return $ Just (info, writer, reader)
                  _ -> return Nothing
              lift $ sendJson info
              let player = GameInfo.player info
              gameRef <- newIORef $ GameInfo.game info
              flip runReaderT gameRef do
                  when (player == Player.A) $ tryEnact player writer
                  completedGame <- untilJust do
                      msg  <- liftIO . atomically $ readTChan reader
                      case msg of
                          Message.Forfeit -> do
                              P.modify . Game.forfeit $ Player.opponent player
                              Just <$> P.game
                          Message.Enact game -> do
                              if not . null $ Game.victor game then
                                  return $ Just game
                              else do
                                  lift . lift . sendJson $ 
                                      GameInfo.censor player game
                                  P.modify $ const game
                                  tryEnact player writer
                                  return Nothing
                  lift . lift . sendJson $ GameInfo.censor player completedGame

-- | Wraps @enact@ with error handling.
tryEnact :: Player -> TChan Message.Game
         -> ReaderT (IORef Game) (ReaderT Random.GenIO (WebSocketsT Handler)) ()
tryEnact player writer = do
    enactText <- lift $ lift WebSockets.receiveData
    case formEnact $ Text.split (=='/') enactText of
        Nothing -> lift . lift $ 
                   WebSockets.sendTextData ("Invalid acts" :: ByteString)
        Just (actChakra, exchangeChakra, actions) -> do
            res <- enact actChakra exchangeChakra actions
            case res of
                Left errorMsg -> lift . lift $ WebSockets.sendTextData errorMsg
                Right () -> do
                    game <- P.game
                    lift . lift . sendJson $ GameInfo.censor player game
                    liftIO . atomically . writeTChan writer $ Message.Enact game

-- | Processes a user's actions and passes them to 'Turn.run'.
enact :: ∀ m. (MonadGame m, MonadRandom m) => Chakras -> Chakras -> [Act]
      -> m (Either Text ())
enact actChakra exchangeChakra actions = do
    player     <- P.player
    gameChakra <- Game.getChakra player <$> P.game
    let chakra  = gameChakra + exchangeChakra - actChakra
    if | not . null $ drop Slot.teamSize actions -> err "Too many actions"
       | duplic $ Act.user <$> actions           -> err "Duplicate actors"
       | any (not . inRange (0, 3)) skills       -> err "Action out of range"
       | randTotal < 0 || Chakra.lack chakra     -> err "Insufficient chakra"
       | any (Act.illegal player) actions        -> err "Character out of range"
       | otherwise                               -> Right <$> do
            P.modify . Game.setChakra player $
                chakra { Chakra.rand = randTotal }
            Turn.run actions
  where
    skills = lefts $ Act.skill <$> actions
    randTotal = Chakra.total actChakra - 5 * Chakra.total exchangeChakra
    err = return . Left
