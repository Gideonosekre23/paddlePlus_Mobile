import axiosInstance from "./axios";

export const checkTokenValidity = async () => {
  try {
      const response = await axiosInstance.get('/rider/token/check/');
      console.log("Success check, with response: ", JSON.stringify(response, null, 2));
      return response.status;
    } catch (error) {
      console.log("Error check, with error: ", JSON.stringify(error, null, 2));

      if (error.response) {
        const reqStatus = error.response.status;
        console.log("Request status: ", reqStatus);
        return reqStatus;
      } else {
        console.log("No response received, error message: ", error.message);
        return null;
      }
    }
};

export const getCustomerInfo = async () => {
  try {
    const response = await axiosInstance.get('/rider/list/');
    return response.data;
  } catch (error) {
    console.warn('Error fetching customer info:', error.response || error.message || error);
    throw error.response ? error.response.data : error;
  }
};

export const registerUser = async (userData, isOwner) => {
  const baseApiString = isOwner ? "owner" : "rider";
  try {
    const response = await axiosInstance.post(`/${baseApiString}/register/`, userData);
    console.log(`REGISTER RESPONSE for ${baseApiString}: `, JSON.stringify(response, null, 2));
    return response.data;
  } catch (error) {
    console.warn('Error registering user:', error.response || error.message || error);
    throw error;
  }
};

export const loginUser = async (credentials, isOwner) => {
  const baseApiString = isOwner ? "owner" : "rider";
  try {
    console.log("Is owner? ", isOwner);
    const response = await axiosInstance.post(`/${baseApiString}/login/`, credentials);
    // const token = response.data.user.token;
    // console.log(token);
    return response.data;
  } catch (error) {
    console.warn('Error logging in user:', error.response || error.message || error);
    throw error;
  }
};

export const getOwnerBikes = async () => {
  try {
    const response = await axiosInstance.get('/bikes/owner/');
    console.log("RESPONSE: ", JSON.stringify(response.data, null, 2));
    return response.data;
  } catch (error) {
    console.warn('Error fetching bikes:', error.response || error.message || error);
    throw error.response ? error.response.data : error;
  }
};

export const addBike = async (bikeData) => {
  try {
    const response = await axiosInstance.post('/bikes/add/', bikeData);
    console.log("ADD BIKE RESPONSE: ", JSON.stringify(response, null, 2));
    return response;
  } catch (error) {
    console.warn('Error add bike:', error.response || error.message || error);
    throw error.response ? error.response.data : error;
  }
};