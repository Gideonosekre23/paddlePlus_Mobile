import { useLocation } from "react-router-dom";
import HomePageRider from "./HomePageRider";
import HomePageOwner from "./HomePageOwner";

const HomePage = () => {
  const location = useLocation();
  const isOwner = location.state?.isOwner;

  return <>{isOwner ? <HomePageOwner /> : <HomePageRider />}</>;
};

export default HomePage