module Pretty where



class PrettyShow a where
  pretty :: a -> String
