import axiosInstance from "./axios";

export const checkTokenValidity = async () => {
  try {
      const response = await axiosInstance.get('rider/token/check/');
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

export const getVerificationStatus = async (username) => {
  const response = await axiosInstance.get(`/rider/verification/status/${username}/`);
  return response.data;
};

export const registerUser = async (userData) => {
  try {
    const response = await axiosInstance.post('/rider/register/', userData);
    console.log("REGISTER RESPONSE: ", JSON.stringify(response, null, 2));
    return response.data;
  } catch (error) {
    console.warn('Error registering user:', error.response || error.message || error);
    throw error;
  }
};

export const loginUser = async (credentials) => {
  try {
    const response = await axiosInstance.post('/rider/login/', credentials);
    // const token = response.data.user.token;
    // console.log(token);
    return response.data;
  } catch (error) {
    console.warn('Error logging in user:', error.response || error.message || error);
    throw error;
  }
};